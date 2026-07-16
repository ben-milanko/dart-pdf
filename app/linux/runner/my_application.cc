#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The top-level window, used to anchor the print dialog.
  GtkWindow* window;
  // Native printing (no bundled PDF engine): the Dart side streams JPEG page
  // images over this channel; endJob spools them through GtkPrintOperation.
  FlMethodChannel* native_print_channel;
  GPtrArray* print_pages;  // GBytes* per accumulated page image
  char* print_job_name;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Drops the accumulated print page buffers.
static void clear_print_pages(MyApplication* self) {
  if (self->print_pages != nullptr) {
    g_ptr_array_set_size(self->print_pages, 0);
  }
}

// Draws one accumulated page image onto the print context, aspect-fitted and
// centred on the sheet.
static void print_draw_page_cb(GtkPrintOperation* operation,
                               GtkPrintContext* context, gint page_nr,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->print_pages == nullptr || page_nr < 0 ||
      static_cast<guint>(page_nr) >= self->print_pages->len) {
    return;
  }
  GBytes* bytes =
      static_cast<GBytes*>(g_ptr_array_index(self->print_pages, page_nr));
  gsize size = 0;
  gconstpointer data = g_bytes_get_data(bytes, &size);

  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  g_autoptr(GError) error = nullptr;
  if (!gdk_pixbuf_loader_write(loader, static_cast<const guchar*>(data), size,
                               &error) ||
      !gdk_pixbuf_loader_close(loader, &error)) {
    return;
  }
  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);  // owned by loader
  if (pixbuf == nullptr) {
    return;
  }

  cairo_t* cr = gtk_print_context_get_cairo_context(context);
  double page_w = gtk_print_context_get_width(context);
  double page_h = gtk_print_context_get_height(context);
  int iw = gdk_pixbuf_get_width(pixbuf);
  int ih = gdk_pixbuf_get_height(pixbuf);
  if (iw <= 0 || ih <= 0) {
    return;
  }
  double scale = MIN(page_w / iw, page_h / ih);
  double draw_w = iw * scale;
  double draw_h = ih * scale;
  cairo_save(cr);
  cairo_translate(cr, (page_w - draw_w) / 2, (page_h - draw_h) / 2);
  cairo_scale(cr, scale, scale);
  gdk_cairo_set_source_pixbuf(cr, pixbuf, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
}

// Shows the print dialog and spools the accumulated pages via GTK. Returns
// FALSE on cancel or error. Clears the job either way.
static gboolean run_print_job(MyApplication* self) {
  if (self->print_pages == nullptr || self->print_pages->len == 0) {
    return FALSE;
  }
  GtkPrintOperation* operation = gtk_print_operation_new();
  gtk_print_operation_set_n_pages(operation,
                                  static_cast<gint>(self->print_pages->len));
  gtk_print_operation_set_job_name(operation, self->print_job_name != nullptr
                                                   ? self->print_job_name
                                                   : "Document");
  g_signal_connect(operation, "draw-page", G_CALLBACK(print_draw_page_cb), self);

  g_autoptr(GError) error = nullptr;
  GtkPrintOperationResult res = gtk_print_operation_run(
      operation, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG, self->window, &error);
  g_object_unref(operation);

  gboolean ok = res != GTK_PRINT_OPERATION_RESULT_ERROR &&
                res != GTK_PRINT_OPERATION_RESULT_CANCEL;
  clear_print_pages(self);
  return ok;
}

// Handles the dev.milanko.dartpdf/native_print channel: beginJob / printPage /
// endJob / cancelJob.
static void native_print_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  gboolean is_map = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP;
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "beginJob") == 0) {
    clear_print_pages(self);
    g_clear_pointer(&self->print_job_name, g_free);
    FlValue* name = is_map ? fl_value_lookup_string(args, "name") : nullptr;
    self->print_job_name =
        (name != nullptr && fl_value_get_type(name) == FL_VALUE_TYPE_STRING)
            ? g_strdup(fl_value_get_string(name))
            : g_strdup("Document");
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "dpi", fl_value_new_int(300));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(info));
  } else if (strcmp(method, "printPage") == 0) {
    FlValue* image = is_map ? fl_value_lookup_string(args, "image") : nullptr;
    if (image == nullptr ||
        fl_value_get_type(image) != FL_VALUE_TYPE_UINT8_LIST) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "printPage expects image bytes", nullptr));
    } else {
      g_ptr_array_add(self->print_pages,
                      g_bytes_new(fl_value_get_uint8_list(image),
                                  fl_value_get_length(image)));
      g_autoptr(FlValue) ok = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(ok));
    }
  } else if (strcmp(method, "endJob") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(run_print_job(self));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else if (strcmp(method, "cancelJob") == 0) {
    clear_print_pages(self);
    g_autoptr(FlValue) value = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send native_print response: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
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

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

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
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->native_print_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/native_print", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->native_print_channel, native_print_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->native_print_channel);
  g_clear_pointer(&self->print_pages, g_ptr_array_unref);
  g_clear_pointer(&self->print_job_name, g_free);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->print_pages =
      g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
