# libjpeg-turbo WebAssembly module

This recipe builds the embedded browser accelerator used for four-component
CMYK/YCCK JPEGs. It pins libjpeg-turbo 3.1.2 by source checksum and uses WASI
SDK 30. The small `cmyk.c` companion applies DartPDF's existing DeviceCMYK
polynomial in bulk; it does not change the renderer's colour semantics.

Build and verify the deterministic module:

```sh
WASI_SDK_PATH=/path/to/wasi-sdk-30.0 \
  ./build.sh /tmp/jpeg-turbo-3.1.2.wasm
```

To refresh `lib/src/jpeg_turbo_wasm_data.dart`, gzip with a zero timestamp
(`gzip -9 -n`) and base64-encode the result as one line. Keep the source and
module SHA-256 values in that generated Dart file in sync with this recipe.

The browser wrapper supplies minimal WASI imports and maps libjpeg's
`setjmp`/`longjmp` error path to a JavaScript exception. Any load or decode
failure leaves the pure-Dart decoder as the correctness fallback.

libjpeg-turbo's upstream `LICENSE.md` and `README.ijg` are included under
`third_party/libjpeg-turbo/`. As required by the IJG terms: this software is
based in part on the work of the Independent JPEG Group.
