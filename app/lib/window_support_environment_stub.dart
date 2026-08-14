/// Whether this process explicitly opted into DartPDF's experimental
/// multi-window bootstrap.
///
/// Web builds and platforms without `dart:io` always use the normal
/// single-window path.
bool get dartPdfWindowingRequested => false;
