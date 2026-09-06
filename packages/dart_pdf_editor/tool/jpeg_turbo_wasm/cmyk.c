#include <stddef.h>
#include <stdint.h>

static uint8_t byte_round(double value) {
  if (value <= 0.0) return 0;
  if (value >= 255.0) return 255;
  return (uint8_t)(value + 0.5);
}

// The SWOP-class DeviceCMYK polynomial used by PdfColor.cmyk, evaluated in
// bulk inside WebAssembly so dart2js does not pay four typed-array reads and
// several dozen floating-point operations per output pixel.
int dartpdf_cmyk_to_rgba(const uint8_t *input, uint8_t *output,
                         size_t pixels) {
  if (input == NULL || output == NULL) return -1;
  for (size_t i = 0; i < pixels; i++) {
    const double c = input[i * 4] / 255.0;
    const double m = input[i * 4 + 1] / 255.0;
    const double y = input[i * 4 + 2] / 255.0;
    const double k = input[i * 4 + 3] / 255.0;

    const double r =
        255.0 +
        c * (-4.387332384609988 * c + 54.48615194189176 * m +
             18.82290502165302 * y + 212.25662451639585 * k -
             285.2331026137004) +
        m * (1.7149763477362134 * m - 5.6096736904047315 * y -
             17.873870861415444 * k - 5.497006427196366) +
        y * (-2.5217340131683033 * y - 21.248923337353073 * k +
             17.5119270841813) +
        k * (-21.86122147463605 * k - 189.48180835922747);

    const double g =
        255.0 +
        c * (8.841041422036149 * c + 60.118027045597366 * m +
             6.871425592049007 * y + 31.159100130055922 * k -
             79.2970844816548) +
        m * (-15.310361306967817 * m + 17.575251261109482 * y +
             131.35250912493976 * k - 190.9453302588951) +
        y * (4.444339102852739 * y + 9.8632861493405 * k -
             24.86741582555878) +
        k * (-20.737325471181034 * k - 187.80453709719578);

    const double b =
        255.0 +
        c * (0.8842522430003296 * c + 8.078677503112928 * m +
             30.89978309703729 * y - 0.23883238689178934 * k -
             14.183576799673286) +
        m * (10.49593273432072 * m + 63.02378494754052 * y +
             50.606957656360734 * k - 112.23884253719248) +
        y * (0.03296041114873217 * y + 115.60384449646641 * k -
             193.58209356861505) +
        k * (-22.33816807309886 * k - 180.12613974708367);

    output[i * 4] = byte_round(r);
    output[i * 4 + 1] = byte_round(g);
    output[i * 4 + 2] = byte_round(b);
    output[i * 4 + 3] = 255;
  }
  return 0;
}

// Exact counterpart of pdf_graphics' component-plane box reducer. libjpeg's
// scaled IDCT emits one of eight fractional sizes; the closest size above a
// display target is often only a few percent larger. Finishing that reduction
// in generated dart2js code was several times slower than the JPEG decode
// itself on real press PDFs. Keep the identical integer-cell average inside
// the module, before copying samples back across the JS/WASM boundary.
int dartpdf_box_downsample(const uint8_t *input, size_t source_width,
                           size_t source_height, size_t components,
                           uint8_t *output, size_t target_width,
                           size_t target_height) {
  if (input == NULL || output == NULL || source_width == 0 ||
      source_height == 0 || components == 0 || components > 8 ||
      target_width == 0 || target_height == 0 ||
      target_width > source_width || target_height > source_height) {
    return -1;
  }

  size_t destination = 0;
  for (size_t target_y = 0; target_y < target_height; target_y++) {
    const size_t source_y0 = target_y * source_height / target_height;
    size_t source_y1 = (target_y + 1) * source_height / target_height;
    if (source_y1 <= source_y0) source_y1 = source_y0 + 1;
    for (size_t target_x = 0; target_x < target_width; target_x++) {
      const size_t source_x0 = target_x * source_width / target_width;
      size_t source_x1 = (target_x + 1) * source_width / target_width;
      if (source_x1 <= source_x0) source_x1 = source_x0 + 1;

      uint64_t sums[8] = {0};
      size_t count = 0;
      for (size_t source_y = source_y0; source_y < source_y1; source_y++) {
        size_t source =
            (source_y * source_width + source_x0) * components;
        for (size_t source_x = source_x0; source_x < source_x1; source_x++) {
          for (size_t component = 0; component < components; component++) {
            sums[component] += input[source + component];
          }
          source += components;
          count++;
        }
      }
      for (size_t component = 0; component < components; component++) {
        output[destination++] = (uint8_t)(sums[component] / count);
      }
    }
  }
  return 0;
}
