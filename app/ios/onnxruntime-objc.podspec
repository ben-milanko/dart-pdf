Pod::Spec.new do |s|
  # Compatibility spec for onnxruntime 1.4.1's exact iOS dependency. The
  # original CocoaPods archives are unavailable. No Objective-C wrapper is
  # needed: the Flutter plugin looks up the C API in the Runner process.
  s.name = 'onnxruntime-objc'
  s.version = '1.15.1'
  s.summary = 'ONNX Runtime C API for the DartPDF iOS FFI plugin'
  s.homepage = 'https://github.com/microsoft/onnxruntime'
  s.authors = { 'ONNX Runtime' => 'onnxruntime@microsoft.com' }
  s.license = { :type => 'MIT', :file => 'LICENSE.txt' }
  s.source = {
    :http => 'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.15.1/microsoft.ml.onnxruntime.1.15.1.nupkg',
    :type => 'zip',
    :sha256 => 'da45c9bf6472637fc97eec243eac979cdc3456d0e4380ecfeffdeec75a627431',
  }
  s.ios.deployment_target = '11.0'
  s.static_framework = true
  s.vendored_frameworks = 'runtimes/ios/native/onnxruntime.xcframework'
  s.weak_frameworks = 'CoreML'
  s.libraries = 'c++'
  s.preserve_paths = 'ThirdPartyNotices.txt'

  # Dart's DynamicLibrary.process lookup does not create a native reference.
  # Force the archive member into Runner and keep the symbol under dead stripping.
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '-Wl,-u,_OrtGetApiBase' }
end
