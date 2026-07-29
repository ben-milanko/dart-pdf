#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cairo.h>

#include <cmath>
#include <cstdio>
#include <cstring>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The top-level window, used to anchor the print dialog and to know whether
  // the UI has already been built (non-null once activated).
  GtkWindow* window;
  // Native printing (no bundled PDF engine): the Dart side streams JPEG page
  // images over this channel; endJob spools them through GtkPrintOperation.
  FlMethodChannel* native_print_channel;
  // Warm-start OS file opens, bridged to the Dart IncomingFileService (the
  // reverse-DNS channel every runner shares) as `openFile`. Cold-start opens
  // arrive as Dart entrypoint arguments instead (see my_application_open), the
  // way the Dart side expects on Windows and Linux.
  FlMethodChannel* incoming_channel;
  // Physical/available memory snapshots for the adaptive PDF cache policy.
  FlMethodChannel* memory_channel;
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

// ---------------------------------------------------------------------------
// Vector op stream (VPR1) replay onto a Cairo print context. The stream (from
// pdf_graphics' encodeVectorPrintPage) is in device points (top-left origin,
// y down, 1 unit = 1 PDF point) with /Rotate and crop already folded in, so we
// only fit-and-centre it into the sheet and issue Cairo paths/text/images.
// ---------------------------------------------------------------------------

namespace {

// A little-endian cursor over the op stream; every read bounds-checks and
// trips `ok` false on overrun so a corrupt buffer aborts cleanly.
struct VpReader {
  const guint8* p;
  const guint8* end;
  bool ok = true;

  bool Remaining(gsize n) {
    if (static_cast<gsize>(end - p) < n) {
      ok = false;
      return false;
    }
    return true;
  }
  guint8 U8() { return Remaining(1) ? *p++ : 0; }
  guint16 U16() {
    if (!Remaining(2)) return 0;
    guint16 v = static_cast<guint16>(p[0] | (p[1] << 8));
    p += 2;
    return v;
  }
  guint32 U32() {
    if (!Remaining(4)) return 0;
    guint32 v = static_cast<guint32>(p[0]) | (static_cast<guint32>(p[1]) << 8) |
                (static_cast<guint32>(p[2]) << 16) |
                (static_cast<guint32>(p[3]) << 24);
    p += 4;
    return v;
  }
  float F32() {
    guint32 bits = U32();
    float v;
    std::memcpy(&v, &bits, sizeof(v));
    return v;
  }
};

// Reads a path into the current Cairo path. Coordinates are stream points.
void vp_read_path(VpReader* r, cairo_t* cr) {
  const guint32 count = r->U32();
  double cx = 0, cy = 0;  // current point, for close-then-continue
  for (guint32 i = 0; i < count && r->ok; i++) {
    switch (r->U8()) {
      case 0: {  // move
        cx = r->F32();
        cy = r->F32();
        cairo_move_to(cr, cx, cy);
        break;
      }
      case 1: {  // line
        cx = r->F32();
        cy = r->F32();
        cairo_line_to(cr, cx, cy);
        break;
      }
      case 2: {  // cubic
        double x1 = r->F32(), y1 = r->F32();
        double x2 = r->F32(), y2 = r->F32();
        double x3 = r->F32(), y3 = r->F32();
        cairo_curve_to(cr, x1, y1, x2, y2, x3, y3);
        cx = x3;
        cy = y3;
        break;
      }
      case 3:  // close
        cairo_close_path(cr);
        break;
      default:
        r->ok = false;
        break;
    }
  }
}

void vp_read_rgba(VpReader* r, double* rr, double* gg, double* bb, double* aa) {
  *rr = r->U8() / 255.0;
  *gg = r->U8() / 255.0;
  *bb = r->U8() / 255.0;
  *aa = r->U8() / 255.0;
}

void vp_replay_fill(VpReader* r, cairo_t* cr) {
  double rr, gg, bb, aa;
  vp_read_rgba(r, &rr, &gg, &bb, &aa);
  const bool even_odd = r->U8() == 1;
  cairo_new_path(cr);
  vp_read_path(r, cr);
  cairo_set_source_rgba(cr, rr, gg, bb, aa);
  cairo_set_fill_rule(
      cr, even_odd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING);
  cairo_fill(cr);
}

void vp_replay_stroke(VpReader* r, cairo_t* cr) {
  double rr, gg, bb, aa;
  vp_read_rgba(r, &rr, &gg, &bb, &aa);
  const double width = r->F32();
  const guint8 cap = r->U8();
  const guint8 join = r->U8();
  cairo_set_miter_limit(cr, r->F32());
  const guint16 dash_count = r->U16();
  double dashes[32];
  int used = 0;
  for (guint16 i = 0; i < dash_count; i++) {
    double d = r->F32();
    if (used < 32) dashes[used++] = d;
  }
  const double dash_phase = r->F32();
  cairo_new_path(cr);
  vp_read_path(r, cr);
  cairo_set_source_rgba(cr, rr, gg, bb, aa);
  cairo_set_line_width(cr, width > 0 ? width : 0.1);
  cairo_set_line_cap(cr, cap == 1 ? CAIRO_LINE_CAP_ROUND
                                  : (cap == 2 ? CAIRO_LINE_CAP_SQUARE
                                              : CAIRO_LINE_CAP_BUTT));
  cairo_set_line_join(cr, join == 1 ? CAIRO_LINE_JOIN_ROUND
                                    : (join == 2 ? CAIRO_LINE_JOIN_BEVEL
                                                 : CAIRO_LINE_JOIN_MITER));
  if (used > 0) {
    cairo_set_dash(cr, dashes, used, dash_phase);
  } else {
    cairo_set_dash(cr, nullptr, 0, 0);
  }
  cairo_stroke(cr);
  cairo_set_dash(cr, nullptr, 0, 0);
}

void vp_replay_clip(VpReader* r, cairo_t* cr) {
  const bool even_odd = r->U8() == 1;
  cairo_new_path(cr);
  vp_read_path(r, cr);
  cairo_set_fill_rule(
      cr, even_odd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING);
  cairo_clip(cr);
}

void vp_replay_text(VpReader* r, cairo_t* cr) {
  double rr, gg, bb, aa;
  vp_read_rgba(r, &rr, &gg, &bb, &aa);
  const guint8 flags = r->U8();
  double m[6];
  for (int i = 0; i < 6; i++) m[i] = r->F32();
  r->F32();  // nominal font size - derived from the matrix below
  const guint16 len = r->U16();
  if (!r->Remaining(len)) return;
  const char* utf8 = reinterpret_cast<const char*>(r->p);
  gsize utf8_len = len;
  r->p += len;
  if (aa == 0 || len == 0) return;

  // The matrix maps em space (1.0 = font size) to device points; place the
  // baseline at (e,f), size = the em-height, rotation = the x-basis angle.
  const double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
  const double size = std::hypot(c, d);
  const double angle = std::atan2(b, a);
  if (size <= 0) return;

  cairo_save(cr);
  cairo_translate(cr, e, f);
  cairo_rotate(cr, angle);
  cairo_select_font_face(
      cr, "sans-serif",
      (flags & 0x02) ? CAIRO_FONT_SLANT_ITALIC : CAIRO_FONT_SLANT_NORMAL,
      (flags & 0x01) ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, size);
  cairo_set_source_rgba(cr, rr, gg, bb, 1.0);
  cairo_move_to(cr, 0, 0);
  g_autofree char* text = g_strndup(utf8, utf8_len);
  cairo_show_text(cr, text);
  cairo_restore(cr);
}

void vp_replay_image(VpReader* r, cairo_t* cr) {
  double m[6];
  for (int i = 0; i < 6; i++) m[i] = r->F32();
  const guint32 w = r->U32();
  const guint32 h = r->U32();
  const gsize pixels = static_cast<gsize>(w) * h * 4;
  if (w == 0 || h == 0 || !r->Remaining(pixels)) return;
  const guint8* rgba = r->p;
  r->p += pixels;

  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return;
  }
  const int stride = cairo_image_surface_get_stride(surface);
  guint8* dst = cairo_image_surface_get_data(surface);
  cairo_surface_flush(surface);
  // Our rows are top-down, premultiplied RGBA; Cairo ARGB32 is premultiplied
  // BGRA in native (little-endian) byte order.
  for (guint32 y = 0; y < h; y++) {
    const guint8* src_row = rgba + static_cast<gsize>(y) * w * 4;
    guint8* dst_row = dst + static_cast<gsize>(y) * stride;
    for (guint32 x = 0; x < w; x++) {
      dst_row[x * 4 + 0] = src_row[x * 4 + 2];  // B
      dst_row[x * 4 + 1] = src_row[x * 4 + 1];  // G
      dst_row[x * 4 + 2] = src_row[x * 4 + 0];  // R
      dst_row[x * 4 + 3] = src_row[x * 4 + 3];  // A
    }
  }
  cairo_surface_mark_dirty(surface);

  cairo_save(cr);
  // Map the unit square (image space, y-up) to device points...
  cairo_matrix_t cm;
  cairo_matrix_init(&cm, m[0], m[1], m[2], m[3], m[4], m[5]);
  cairo_transform(cr, &cm);
  // ...then map the surface pixel grid (top-down) into that unit square,
  // flipping y (row 0 = top = v 1).
  cairo_matrix_t sm;
  cairo_matrix_init(&sm, 1.0 / w, 0, 0, -1.0 / h, 0, 1);
  cairo_transform(cr, &sm);
  cairo_set_source_surface(cr, surface, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
  cairo_surface_destroy(surface);
}

// Replays one page's op stream onto |cr|, fit-and-centred into a page of
// |page_w| x |page_h| points. Returns false on a bad header.
bool draw_vector_page(cairo_t* cr, const guint8* data, gsize size,
                      double page_w, double page_h) {
  VpReader r{data, data + size};
  if (r.U8() != 'V' || r.U8() != 'P' || r.U8() != 'R' || r.U8() != 1) {
    return false;
  }
  const double doc_w = r.F32();
  const double doc_h = r.F32();
  if (!r.ok || doc_w <= 0 || doc_h <= 0) return false;

  const double fit = MIN(page_w / doc_w, page_h / doc_h);
  cairo_save(cr);
  cairo_translate(cr, (page_w - doc_w * fit) / 2.0,
                  (page_h - doc_h * fit) / 2.0);
  cairo_scale(cr, fit, fit);

  while (r.ok && r.p < r.end) {
    switch (r.U8()) {
      case 0x01:
        cairo_save(cr);
        break;
      case 0x02:
        cairo_restore(cr);
        break;
      case 0x10:
        vp_replay_fill(&r, cr);
        break;
      case 0x11:
        vp_replay_stroke(&r, cr);
        break;
      case 0x12:
        vp_replay_clip(&r, cr);
        break;
      case 0x20:
        vp_replay_text(&r, cr);
        break;
      case 0x30:
        vp_replay_image(&r, cr);
        break;
      default:
        r.ok = false;
        break;
    }
  }
  cairo_restore(cr);
  return true;
}

// A page stream begins with the VPR1 magic; a raster page begins with a JPEG
// (0xFF 0xD8) or PNG (0x89 'P') signature, so the first bytes disambiguate.
bool is_vector_page(gconstpointer data, gsize size) {
  if (size < 4) return false;
  const guint8* b = static_cast<const guint8*>(data);
  return b[0] == 'V' && b[1] == 'P' && b[2] == 'R' && b[3] == 1;
}

}  // namespace

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

  // A vector op stream replays straight onto the Cairo context (crisp,
  // selectable); a raster page is decoded and blitted.
  if (is_vector_page(data, size)) {
    cairo_t* cr = gtk_print_context_get_cairo_context(context);
    draw_vector_page(cr, static_cast<const guint8*>(data), size,
                     gtk_print_context_get_width(context),
                     gtk_print_context_get_height(context));
    return;
  }

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
    // Report that this runner can replay the vector op stream, so the Dart
    // side sends `printPageVector` and we print vector rather than rasterise.
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "dpi", fl_value_new_int(300));
    fl_value_set_string_take(info, "vector", fl_value_new_bool(TRUE));
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
  } else if (strcmp(method, "printPageVector") == 0) {
    FlValue* page = is_map ? fl_value_lookup_string(args, "page") : nullptr;
    if (page == nullptr ||
        fl_value_get_type(page) != FL_VALUE_TYPE_UINT8_LIST) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "printPageVector expects a byte stream", nullptr));
    } else {
      g_ptr_array_add(self->print_pages,
                      g_bytes_new(fl_value_get_uint8_list(page),
                                  fl_value_get_length(page)));
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

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single-instance: a second launch (the `open` handler activates us, or the
  // user re-runs the binary) reuses the window that already exists.
  if (self->window != nullptr) {
    gtk_window_present(self->window);
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

  // Bridge OS file opens to the Dart IncomingFileService.
  self->incoming_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/incoming", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->incoming_channel, incoming_method_call_cb, self, nullptr);

  self->memory_channel = fl_method_channel_new(
      messenger, "dev.milanko.dartpdf/memory", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->memory_channel, memory_method_call_cb, self, nullptr);

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

  if (self->window == nullptr) {
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
    gtk_window_present(self->window);
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
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->native_print_channel);
  g_clear_object(&self->incoming_channel);
  g_clear_object(&self->memory_channel);
  g_clear_pointer(&self->print_pages, g_ptr_array_unref);
  g_clear_pointer(&self->print_job_name, g_free);
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
  self->print_pages =
      g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref);
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
