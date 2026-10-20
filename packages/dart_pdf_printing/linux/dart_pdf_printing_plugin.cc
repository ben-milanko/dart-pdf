#include "include/dart_pdf_printing/dart_pdf_printing_plugin.h"
#include <cairo.h>
#include <cmath>
#include <cstdint>
#include <cstring>

struct _DartPdfPrintingPlugin {
  GObject parent_instance;
  GWeakRef view;
  GPtrArray* print_pages;
  char* print_job_name;
  gboolean use_document_page_size;
};
G_DEFINE_TYPE(DartPdfPrintingPlugin, dart_pdf_printing_plugin, G_TYPE_OBJECT)

static GtkWindow* print_owner(DartPdfPrintingPlugin* self) {
  // Multi-window engines need not have an implicit registrar view.
  auto* app = g_application_get_default();
  if (GTK_IS_APPLICATION(app)) {
    auto* window = gtk_application_get_active_window(GTK_APPLICATION(app));
    if (window != nullptr) return window;
  }
  auto* view = static_cast<GObject*>(g_weak_ref_get(&self->view));
  if (view == nullptr) return nullptr;
  auto* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  g_object_unref(view);
  return GTK_IS_WINDOW(top) ? GTK_WINDOW(top) : nullptr;
}

// Drops the accumulated print page buffers.
static void clear_print_pages(DartPdfPrintingPlugin* self) {
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
                      double page_w, double page_h,
                      bool use_document_page_size) {
  if (size < 12) return false;
  VpReader r{data, data + size};
  if (r.U8() != 'V' || r.U8() != 'P' || r.U8() != 'R' || r.U8() != 1) {
    return false;
  }
  const double doc_w = r.F32();
  const double doc_h = r.F32();
  if (!r.ok || !std::isfinite(doc_w) || !std::isfinite(doc_h) ||
      doc_w <= 0 || doc_h <= 0) return false;

  const double fit = use_document_page_size
                         ? 1.0 : MIN(page_w / doc_w, page_h / doc_h);
  cairo_save(cr);
  if (!use_document_page_size) {
    cairo_translate(cr, (page_w - doc_w * fit) / 2.0,
                    (page_h - doc_h * fit) / 2.0);
  }
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

bool vector_page_size(GBytes* bytes, double* width, double* height) {
  gsize size = 0;
  gconstpointer data = g_bytes_get_data(bytes, &size);
  if (size < 12 || !is_vector_page(data, size)) return false;
  const auto* b = static_cast<const guint8*>(data);
  VpReader r{b + 4, b + size};
  *width = r.F32();
  *height = r.F32();
  return r.ok && std::isfinite(*width) && std::isfinite(*height) &&
         *width > 0 && *height > 0;
}

GtkPaperSize* paper_for_dimensions(double width, double height) {
  const double short_side = MIN(width, height);
  const double long_side = MAX(width, height);
  // Keep named tray media recognizable to CUPS instead of advertising every
  // standard sheet as a custom form. Allow 0.1 mm for the f32 stream header.
  const char* const standard_names[] = {
      "iso_a0", "iso_a1", "iso_a2", "iso_a3", "iso_a4", "iso_a5", "iso_a6",
      "na_letter", "na_legal", "na_ledger",
  };
  for (const char* name : standard_names) {
    GtkPaperSize* paper = gtk_paper_size_new(name);
    if (std::abs(gtk_paper_size_get_width(paper, GTK_UNIT_POINTS) - short_side) <
            72.0 / 254.0 &&
        std::abs(gtk_paper_size_get_height(paper, GTK_UNIT_POINTS) - long_side) <
            72.0 / 254.0) {
      return paper;
    }
    gtk_paper_size_free(paper);
  }
  // gtk_paper_size_is_equal compares custom papers by NAME, not dimensions.
  // Give different media distinct names so mixed-size sheets do not compare
  // equal. Locale-independent round-trip strings keep the identity stable.
  char width_name[G_ASCII_DTOSTR_BUF_SIZE];
  char height_name[G_ASCII_DTOSTR_BUF_SIZE];
  g_ascii_dtostr(width_name, sizeof(width_name), short_side);
  g_ascii_dtostr(height_name, sizeof(height_name), long_side);
  g_autofree char* name =
      g_strdup_printf("dartpdf-sheet-%sx%s", width_name, height_name);
  return gtk_paper_size_new_custom(name, "Document sheet", short_side,
                                    long_side, GTK_UNIT_POINTS);
}

}  // namespace

// Draws one accumulated page image onto the print context, aspect-fitted and
// centred on the sheet.
static void print_draw_page_cb(GtkPrintOperation* operation,
                               GtkPrintContext* context, gint page_nr,
                               gpointer user_data) {
  DartPdfPrintingPlugin* self = reinterpret_cast<DartPdfPrintingPlugin*>(user_data);
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
                     gtk_print_context_get_height(context),
                     self->use_document_page_size);
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

// Prepared stream coordinates already describe the physical sheet. GTK calls
// this before each page, allowing a mixed-size PDF to choose matching media
// without applying another fit-to-printable-area transform.
static void print_page_setup_cb(GtkPrintOperation* operation,
                                GtkPrintContext* context, gint page_nr,
                                GtkPageSetup* setup, gpointer user_data) {
  DartPdfPrintingPlugin* self = reinterpret_cast<DartPdfPrintingPlugin*>(user_data);
  if (!self->use_document_page_size || self->print_pages == nullptr ||
      page_nr < 0 || static_cast<guint>(page_nr) >= self->print_pages->len) {
    return;
  }
  auto* bytes = static_cast<GBytes*>(
      g_ptr_array_index(self->print_pages, page_nr));
  double width = 0, height = 0;
  if (!vector_page_size(bytes, &width, &height)) return;
  GtkPaperSize* paper = paper_for_dimensions(width, height);
  gtk_page_setup_set_paper_size(setup, paper);
  gtk_paper_size_free(paper);
  gtk_page_setup_set_orientation(setup, width > height
      ? GTK_PAGE_ORIENTATION_LANDSCAPE : GTK_PAGE_ORIENTATION_PORTRAIT);
  gtk_page_setup_set_top_margin(setup, 0, GTK_UNIT_POINTS);
  gtk_page_setup_set_bottom_margin(setup, 0, GTK_UNIT_POINTS);
  gtk_page_setup_set_left_margin(setup, 0, GTK_UNIT_POINTS);
  gtk_page_setup_set_right_margin(setup, 0, GTK_UNIT_POINTS);
}

// Shows the print dialog and spools the accumulated pages via GTK. Returns
// FALSE on cancel or error. Clears the job either way.
static gboolean run_print_job(DartPdfPrintingPlugin* self) {
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
  if (self->use_document_page_size) {
    gtk_print_operation_set_unit(operation, GTK_UNIT_POINTS);
    gtk_print_operation_set_use_full_page(operation, TRUE);
    GtkPageSetup* setup = gtk_page_setup_new();
    print_page_setup_cb(operation, nullptr, 0, setup, self);
    gtk_print_operation_set_default_page_setup(operation, setup);
    g_object_unref(setup);
    g_signal_connect(operation, "request-page-setup",
                     G_CALLBACK(print_page_setup_cb), self);
    // Page selection, order, copies and n-up were composed in Dart already.
    GtkPrintSettings* settings = gtk_print_settings_new();
    gtk_print_settings_set_n_copies(settings, 1);
    gtk_print_settings_set_collate(settings, FALSE);
    gtk_print_settings_set_reverse(settings, FALSE);
    gtk_print_settings_set_scale(settings, 100);
    gtk_print_settings_set_number_up(settings, 1);
    gtk_print_settings_set_page_set(settings, GTK_PAGE_SET_ALL);
    gtk_print_settings_set_print_pages(settings, GTK_PRINT_PAGES_ALL);
    gtk_print_operation_set_print_settings(operation, settings);
    g_object_unref(settings);
  }

  g_autoptr(GError) error = nullptr;
  GtkPrintOperationResult res = gtk_print_operation_run(
      operation, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG, print_owner(self), &error);
  g_object_unref(operation);

  gboolean ok = res != GTK_PRINT_OPERATION_RESULT_ERROR &&
                res != GTK_PRINT_OPERATION_RESULT_CANCEL;
  clear_print_pages(self);
  return ok;
}

// Handles the dev.milanko.dart_pdf_printing channel: beginJob / printPage /
// endJob / cancelJob.
static void native_print_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  DartPdfPrintingPlugin* self = reinterpret_cast<DartPdfPrintingPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  gboolean is_map = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP;
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "beginJob") == 0) {
    clear_print_pages(self);
    g_clear_pointer(&self->print_job_name, g_free);
    FlValue* prepared = is_map
        ? fl_value_lookup_string(args, "useDocumentPageSize") : nullptr;
    self->use_document_page_size = prepared != nullptr &&
        fl_value_get_type(prepared) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(prepared);
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


static void dart_pdf_printing_plugin_dispose(GObject* object) {
  auto* self = reinterpret_cast<DartPdfPrintingPlugin*>(object);
  g_clear_pointer(&self->print_pages, g_ptr_array_unref);
  g_clear_pointer(&self->print_job_name, g_free);
  G_OBJECT_CLASS(dart_pdf_printing_plugin_parent_class)->dispose(object);
}
static void dart_pdf_printing_plugin_finalize(GObject* object) {
  auto* self = reinterpret_cast<DartPdfPrintingPlugin*>(object);
  g_weak_ref_clear(&self->view);
  G_OBJECT_CLASS(dart_pdf_printing_plugin_parent_class)->finalize(object);
}
static void dart_pdf_printing_plugin_class_init(DartPdfPrintingPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = dart_pdf_printing_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = dart_pdf_printing_plugin_finalize;
}
static void dart_pdf_printing_plugin_init(DartPdfPrintingPlugin* self) {
  g_weak_ref_init(&self->view, nullptr);
  self->print_pages = g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref);
}
void dart_pdf_printing_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* self = reinterpret_cast<DartPdfPrintingPlugin*>(
      g_object_new(dart_pdf_printing_plugin_get_type(), nullptr));
  g_weak_ref_set(&self->view, fl_plugin_registrar_get_view(registrar));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "dev.milanko.dart_pdf_printing",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, native_print_method_call_cb,
      self, g_object_unref);
}
