#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cairo.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "flutter/generated_plugin_registrant.h"
#include "../../native/windowing_bootstrap.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The experimental windowing runner starts one engine without a template
  // FlView. Dart then creates every GtkWindow/FlView pair through Flutter's
  // RegularWindowController implementation.
  FlEngine* windowing_engine;
  gboolean engine_started;
  gboolean application_held;
  // The top-level window, used to anchor the print dialog and to know whether
  // the UI has already been built (non-null once activated).
  GtkWindow* window;
  // Warm-start OS file opens, bridged to the Dart IncomingFileService (the
  // reverse-DNS channel every runner shares) as `openFile`. Cold-start opens
  // arrive as Dart entrypoint arguments instead (see my_application_open), the
  // way the Dart side expects on Windows and Linux.
  FlMethodChannel* incoming_channel;
  // Physical/available memory snapshots for the adaptive PDF cache policy.
  FlMethodChannel* memory_channel;
  FlMethodChannel* image_clipboard_channel;
  // Resolves a tab-drag pointer back to a Dart-owned GtkWindow/FlView.
  FlMethodChannel* window_geometry_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean experimental_windowing_enabled() {
  return dart_pdf::FlutterWindowingEnabled();
}

// Builds the {name, path} payload the Dart side's IncomingFileService decodes,
// matching the Windows/macOS runners.
static FlValue* file_payload(const char* path) {
  g_autofree char* base = g_path_get_basename(path);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "name", fl_value_new_string(base));
  fl_value_set_string_take(map, "path", fl_value_new_string(path));
  return map;
}

// Handles the dev.milanko.dartpdf/incoming channel. On Linux the cold-start
// file arrives as a Dart entrypoint argument (handled by the app itself), so
// `getInitialFile` has nothing to hand back; warm-start opens are pushed from
// the GApplication `open` handler as `openFile`.
static void incoming_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "getInitialFile") == 0) {
    g_autoptr(FlValue) nothing = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nothing));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send incoming response: %s", error->message);
  }
}

// Reads Linux's authoritative available-memory estimate. MemAvailable includes
// reclaimable page cache, unlike MemFree, and is therefore the useful signal
// for deciding whether reconstructed PDF rasters may grow.
static void memory_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "snapshot") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else {
    g_autofree gchar* contents = nullptr;
    gsize length = 0;
    if (!g_file_get_contents("/proc/meminfo", &contents, &length, nullptr)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "memory_snapshot_failed", "Could not read /proc/meminfo", nullptr));
    } else {
      guint64 total_kb = 0;
      guint64 available_kb = 0;
      gchar** lines = g_strsplit(contents, "\n", -1);
      for (gchar** line = lines; *line != nullptr; line++) {
        if (sscanf(*line, "MemTotal: %" G_GUINT64_FORMAT " kB", &total_kb) ==
            1) {
          continue;
        }
        sscanf(*line, "MemAvailable: %" G_GUINT64_FORMAT " kB",
               &available_kb);
      }
      g_strfreev(lines);
      const guint64 total = total_kb * 1024;
      const guint64 available = available_kb * 1024;
      const guint64 low_threshold =
          MAX(static_cast<guint64>(256) * 1024 * 1024, total / 20);
      g_autoptr(FlValue) snapshot = fl_value_new_map();
      fl_value_set_string_take(
          snapshot, "physicalBytes",
          fl_value_new_int(static_cast<gint64>(total)));
      fl_value_set_string_take(
          snapshot, "availableBytes",
          fl_value_new_int(static_cast<gint64>(available)));
      fl_value_set_string_take(snapshot, "lowMemory",
                               fl_value_new_bool(available < low_threshold));
      response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(snapshot));
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send memory response: %s", error->message);
  }
}

static GtkWidget* find_flutter_view(GtkWidget* widget) {
  if (widget == nullptr) return nullptr;
  if (FL_IS_VIEW(widget)) return widget;
  if (!GTK_IS_CONTAINER(widget)) return nullptr;
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  GtkWidget* result = nullptr;
  for (GList* child = children; child != nullptr && result == nullptr;
       child = child->next) {
    result = find_flutter_view(GTK_WIDGET(child->data));
  }
  g_list_free(children);
  return result;
}

// Coordinates are not reliably global on Wayland. Ask GDK for the actual
// surface under the pointer, match its GtkWindow against Flutter 3.47's
// windowHandle values, then read the pointer relative to that window's FlView.
static void window_geometry_method_call_cb(FlMethodChannel* channel,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* handles =
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(args, "handles")
          : nullptr;
  if (strcmp(method, "locateDrop") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else if (handles == nullptr ||
             fl_value_get_type(handles) != FL_VALUE_TYPE_LIST) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad_args", "locateDrop expects a handles list", nullptr));
  } else {
    GdkDisplay* display = gdk_display_get_default();
    GdkSeat* seat = display == nullptr
                        ? nullptr
                        : gdk_display_get_default_seat(display);
    GdkDevice* pointer = seat == nullptr ? nullptr : gdk_seat_get_pointer(seat);
    gint ignored_x = 0;
    gint ignored_y = 0;
    GdkWindow* under = pointer == nullptr
                           ? nullptr
                           : gdk_device_get_window_at_position(
                                 pointer, &ignored_x, &ignored_y);
    GtkWidget* under_widget = nullptr;
    if (under != nullptr) {
      gdk_window_get_user_data(under,
                               reinterpret_cast<gpointer*>(&under_widget));
    }
    GtkWidget* top = under_widget == nullptr
                         ? nullptr
                         : gtk_widget_get_toplevel(under_widget);
    const gint64 top_address = static_cast<gint64>(
        reinterpret_cast<intptr_t>(top));
    gboolean registered = FALSE;
    for (size_t i = 0; i < fl_value_get_length(handles); i++) {
      FlValue* value = fl_value_get_list_value(handles, i);
      if (fl_value_get_type(value) == FL_VALUE_TYPE_INT &&
          fl_value_get_int(value) == top_address) {
        registered = TRUE;
        break;
      }
    }

    GtkWidget* view = registered ? find_flutter_view(top) : nullptr;
    GdkWindow* view_window =
        view == nullptr ? nullptr : gtk_widget_get_window(view);
    if (view_window == nullptr || pointer == nullptr) {
      g_autoptr(FlValue) nothing = fl_value_new_null();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nothing));
    } else {
      gdouble local_x = 0;
      gdouble local_y = 0;
      GdkModifierType mask = static_cast<GdkModifierType>(0);
      gdk_window_get_device_position_double(
          view_window, pointer, &local_x, &local_y, &mask);
      g_autoptr(FlValue) location = fl_value_new_map();
      fl_value_set_string_take(location, "handle",
                               fl_value_new_int(top_address));
      fl_value_set_string_take(location, "x", fl_value_new_float(local_x));
      fl_value_set_string_take(location, "y", fl_value_new_float(local_y));
      response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(location));
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send window geometry response: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void present_existing_window(MyApplication* self) {
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }

  // Flutter's Dart-owned RegularWindows are plain GTK toplevels rather than
  // GtkApplicationWindows, so they do not appear in
  // gtk_application_get_windows(). Surface the active one (or any visible one)
  // when a second process forwards a file to the headless runner.
  GList* windows = gtk_window_list_toplevels();
  GtkWindow* candidate = nullptr;
  for (GList* link = windows; link != nullptr; link = link->next) {
    if (!GTK_IS_WINDOW(link->data) ||
        !gtk_widget_get_visible(GTK_WIDGET(link->data))) {
      continue;
    }
    candidate = GTK_WINDOW(link->data);
    if (gtk_window_is_active(candidate)) break;
  }
  if (candidate != nullptr) gtk_window_present(candidate);
  g_list_free(windows);
}

// The selection owner holds both representations until another application
// replaces them. GTK requests data lazily on X11 and Wayland.
struct SnapshotClipboardData {
  GBytes* pdf;
  GBytes* png;
};
static SnapshotClipboardData* local_snapshot = nullptr;
static gint64 clipboard_generation = 1;
static gint64 local_copy_generation = 0;
struct PendingPdfRead {
  FlMethodCall* call;
  gint64 generation;
};

static void snapshot_get(GtkClipboard*, GtkSelectionData* selection,
                         guint info, gpointer user_data) {
  auto* data = static_cast<SnapshotClipboardData*>(user_data);
  GBytes* bytes = info == 0 ? data->pdf : data->png;
  if (bytes == nullptr) return;
  gsize length = 0;
  const auto* buffer = static_cast<const guint8*>(g_bytes_get_data(bytes, &length));
  gtk_selection_data_set(selection, gtk_selection_data_get_target(selection),
                         8, buffer, static_cast<gint>(length));
}

static void snapshot_clear(GtkClipboard*, gpointer user_data) {
  auto* data = static_cast<SnapshotClipboardData*>(user_data);
  if (local_snapshot == data) local_snapshot = nullptr;
  if (data->pdf != nullptr) g_bytes_unref(data->pdf);
  g_bytes_unref(data->png);
  delete data;
}

static bool clipboard_bytes(FlValue* value) {
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_UINT8_LIST &&
         fl_value_get_length(value) > 0 && fl_value_get_length(value) <= G_MAXINT;
}

static void image_clipboard_method_call_cb(FlMethodChannel*, FlMethodCall* call,
                                           gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(method, "copySnapshot") == 0 || strcmp(method, "copyPng") == 0) {
    const bool snapshot = strcmp(method, "copySnapshot") == 0;
    const bool map = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP;
    FlValue* pdf = snapshot && map ? fl_value_lookup_string(args, "pdf") : nullptr;
    FlValue* png = snapshot
        ? (map ? fl_value_lookup_string(args, "png") : nullptr) : args;
    if (!clipboard_bytes(png) || (snapshot && !clipboard_bytes(pdf))) {
      fl_method_call_respond_error(call, "bad_args", "Expected PDF/PNG bytes",
                                   nullptr, nullptr);
      return;
    }
    auto* data = new SnapshotClipboardData{
        pdf ? g_bytes_new(fl_value_get_uint8_list(pdf), fl_value_get_length(pdf)) : nullptr,
        g_bytes_new(fl_value_get_uint8_list(png), fl_value_get_length(png))};
    GtkTargetEntry targets[] = {
        {const_cast<gchar*>("application/pdf"), 0, 0},
        {const_cast<gchar*>("image/png"), 0, 1}};
    const bool copied = gtk_clipboard_set_with_data(clipboard,
        snapshot ? targets : targets + 1, snapshot ? 2 : 1,
        snapshot_get, snapshot_clear, data);
    if (copied) {
      local_snapshot = data;
      gtk_clipboard_set_can_store(clipboard, nullptr, 0);
    } else {
      snapshot_clear(clipboard, data);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(copied);
    fl_method_call_respond_success(call, result, nullptr);
  } else if (strcmp(method, "markLocalCopy") == 0) {
    local_copy_generation = clipboard_generation;
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "readPdf") == 0) {
    if (local_snapshot != nullptr || local_copy_generation == clipboard_generation) {
      fl_method_call_respond_success(call, nullptr, nullptr);
      return;
    }
    // Retain the method call until GTK delivers the external selection.
    gtk_clipboard_request_contents(clipboard, gdk_atom_intern_static_string("application/pdf"),
        [](GtkClipboard*, GtkSelectionData* selection, gpointer user_data) {
          auto* pending = static_cast<PendingPdfRead*>(user_data);
          const gint length = gtk_selection_data_get_length(selection);
          g_autoptr(FlValue) value = nullptr;
          if (length > 0 && pending->generation == clipboard_generation) {
            value = fl_value_new_map();
            fl_value_set_string_take(value, "pdf",
                fl_value_new_uint8_list(gtk_selection_data_get_data(selection), length));
            fl_value_set_string_take(value, "changeToken", fl_value_new_int(pending->generation));
          }
          fl_method_call_respond_success(pending->call, value, nullptr);
          g_object_unref(pending->call);
          delete pending;
        }, new PendingPdfRead{FL_METHOD_CALL(g_object_ref(call)), clipboard_generation});
  } else if (strcmp(method, "readImage") == 0) {
    gtk_clipboard_request_image(clipboard,
        [](GtkClipboard*, GdkPixbuf* image, gpointer user_data) {
          auto* pending = FL_METHOD_CALL(user_data);
          gchar* png = nullptr;
          gsize length = 0;
          g_autoptr(FlValue) value = nullptr;
          if (image != nullptr && gdk_pixbuf_save_to_buffer(image, &png, &length,
                                                           "png", nullptr, nullptr)) {
            value = fl_value_new_uint8_list(reinterpret_cast<const guint8*>(png), length);
          }
          g_free(png);
          fl_method_call_respond_success(pending, value, nullptr);
          g_object_unref(pending);
        }, g_object_ref(call));
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

static void register_platform_channels(MyApplication* self,
                                       FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  static bool clipboard_signals_connected = false;
  if (!clipboard_signals_connected) {
    g_signal_connect(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), "owner-change",
        G_CALLBACK(+[](GtkClipboard*, GdkEventOwnerChange*, gpointer) {
          ++clipboard_generation;
        }), nullptr);
    clipboard_signals_connected = true;
  }
  self->image_clipboard_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/image_clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->image_clipboard_channel,
      image_clipboard_method_call_cb, self, nullptr);
  self->incoming_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/incoming", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->incoming_channel, incoming_method_call_cb, self, nullptr);

  self->memory_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/memory", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->memory_channel, memory_method_call_cb, self, nullptr);

  self->window_geometry_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/window_geometry",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_geometry_channel, window_geometry_method_call_cb, self,
      nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single-instance: a second launch (the `open` handler activates us, or the
  // user re-runs the binary) reuses the window that already exists.
  if (self->engine_started) {
    present_existing_window(self);
    return;
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  if (experimental_windowing_enabled()) {
    // fl_engine_new_headless starts the engine without installing an implicit
    // view. This is the Linux equivalent of the engine-owned bootstrap used
    // by Flutter's Windows and macOS multi-window examples.
    self->windowing_engine = fl_engine_new_headless(project);
    if (self->windowing_engine == nullptr) {
      g_warning("Failed to start DartPDF's windowing engine");
      g_application_quit(application);
      return;
    }
    fl_register_plugins(FL_PLUGIN_REGISTRY(self->windowing_engine));
    register_platform_channels(
        self,
        fl_engine_get_binary_messenger(self->windowing_engine));
    self->engine_started = TRUE;

    // Without a GtkApplicationWindow owned by this application, GApplication
    // would otherwise drop its last reference before Dart creates the primary
    // RegularWindow. System.exitApplication releases the run loop via
    // g_application_quit when the final Dart-owned window closes.
    g_application_hold(application);
    self->application_held = TRUE;
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "DartPDF");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "DartPDF");
  }

  gtk_window_set_default_size(window, 1280, 720);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Register the native print channel on this view's engine.
  self->window = window;
  FlEngine* engine = fl_view_get_engine(view);
  register_platform_channels(self, fl_engine_get_binary_messenger(engine));
  self->engine_started = TRUE;

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open. Fires for a file-manager "Open With", a
// `dartpdf file.pdf` command line, or a second launch while already running
// (G_APPLICATION_HANDLES_OPEN routes those into this primary instance).
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);

  // Take the first argument that resolves to a local path; skip non-file URIs
  // (g_file_get_path returns null for those). We open a single document.
  char* path = nullptr;
  for (gint i = 0; i < n_files && path == nullptr; i++) {
    path = g_file_get_path(files[i]);
  }

  if (!self->engine_started) {
    // Cold start: deliver the file the way the Dart side reads it on Linux -
    // as an entrypoint argument (see editor_screen.dart's _openLaunchArgs) -
    // then build the UI. dart_entrypoint_arguments is consumed in activate.
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    if (path != nullptr) {
      char* argv[] = {path, nullptr};
      self->dart_entrypoint_arguments = g_strdupv(argv);
    }
    g_free(path);
    g_application_activate(application);
  } else {
    // Warm start into the running instance: hand the file to Dart and raise.
    if (path != nullptr && self->incoming_channel != nullptr) {
      g_autoptr(FlValue) payload = file_payload(path);
      fl_method_channel_invoke_method(self->incoming_channel, "openFile",
                                      payload, nullptr, nullptr, nullptr);
    }
    g_free(path);
    present_existing_window(self);
  }
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->application_held) {
    self->application_held = FALSE;
    g_application_release(application);
  }

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  if (local_snapshot != nullptr) {
    gtk_clipboard_store(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  }
  g_clear_object(&self->image_clipboard_channel);
  g_clear_object(&self->incoming_channel);
  g_clear_object(&self->memory_channel);
  g_clear_object(&self->window_geometry_channel);
  g_clear_object(&self->windowing_engine);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // HANDLES_OPEN: the OS hands us files (a "dartpdf file.pdf" launch or a file
  // manager's "Open With") through the `open` vfunc, and a second invocation
  // is routed into this already-running instance rather than starting a new
  // process (see my_application_open / my_application_activate).
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
