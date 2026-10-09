# Maintainer: Ben Milanko <ben.milanko@protonmail.com>
pkgname=dartpdf-bin
pkgver=8.0.0
pkgrel=1
pkgdesc='Local PDF editor with annotations, forms, signatures and redaction'
arch=('x86_64')
url="https://dart-pdf.com"
license=('Apache-2.0')
# Direct ELF providers verified on Arch, plus the installed icon hierarchy.
# Keep the complete upstream bundle, including its native plugins.
depends=('at-spi2-core' 'cairo' 'fontconfig' 'gdk-pixbuf2' 'glib2' 'glibc'
         'gtk3' 'harfbuzz' 'hicolor-icon-theme' 'libepoxy' 'libgcc'
         'libsecret' 'libstdc++' 'pango' 'zlib')
makedepends=('patchelf')
# The bundled JNI helper links libjvm.so. Validate its runtime requirement
# separately rather than attributing it to OCR without evidence.
optdepends=('org.freedesktop.secrets: store digital-signing identities in a keyring'
            'java-runtime: JVM for the bundled JNI helper')
provides=('dartpdf')
conflicts=('dartpdf')
options=('!strip' '!debug')  # preserve upstream binaries without an empty debug package

source=("dartpdf-${pkgver}.tar.gz::https://github.com/ben-milanko/dart-pdf/releases/download/app-v${pkgver}/dartpdf-linux-x64.tar.gz"
        "LICENSE::https://raw.githubusercontent.com/ben-milanko/dart-pdf/app-v${pkgver}/LICENSE")

sha256sums=('3bb2bf6b940020de29ba45101680b70f758e83090b3b18eb09541c1c80b414f2'
            'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30')

package() {
  # The release tarball extracts the runner, data/, lib/, and share/ straight
  # into $srcdir. Install the runtime bundle under /usr/lib/dartpdf; the
  # runner resolves its real path via readlink and finds data/ + lib/ next to
  # it, so a /usr/bin symlink works.
  install -d "${pkgdir}/usr/lib/dartpdf"
  cp -r "${srcdir}/dart_pdf_editor_app" "${srcdir}/data" "${srcdir}/lib" \
        "${pkgdir}/usr/lib/dartpdf/"
  chmod 755 "${pkgdir}/usr/lib/dartpdf/dart_pdf_editor_app"

  # Flutter plugins contain an upstream CI build directory in RUNPATH.
  # Resolve the bundled engine beside each plugin, not from a writable home.
  local _plugin
  for _plugin in dart_pdf_printing desktop_drop file_selector_linux \
                 flutter_doc_scanner flutter_secure_storage_linux url_launcher_linux; do
    patchelf --set-rpath '$ORIGIN' \
      "${pkgdir}/usr/lib/dartpdf/lib/lib${_plugin}_plugin.so"
  done

  install -d "${pkgdir}/usr/bin"
  ln -s /usr/lib/dartpdf/dart_pdf_editor_app "${pkgdir}/usr/bin/dartpdf"
  # Release 8.0.0 includes the CLI. Fail rather than silently omit it.
  install -Dm755 "${srcdir}/dartpdf-cli" \
    "${pkgdir}/usr/lib/dartpdf/dartpdf-cli"
  ln -s /usr/lib/dartpdf/dartpdf-cli "${pkgdir}/usr/bin/dartpdf-cli"

  install -d "${pkgdir}/usr/share"
  cp -r "${srcdir}/share/." "${pkgdir}/usr/share/"

  install -Dm644 "${srcdir}/LICENSE" \
    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
