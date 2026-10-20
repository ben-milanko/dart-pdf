Pod::Spec.new do |s|
  s.name = 'dart_pdf_printing'
  s.version = '0.1.0'
  s.summary = 'Native system PDF printing for Flutter.'
  s.description = 'Optional native printing with no bundled third-party PDF engine.'
  s.homepage = 'https://github.com/ben-milanko/dart-pdf'
  s.license = { :file => '../LICENSE' }
  s.author = 'Ben Milanko'
  s.source = { :path => '.' }
  s.source_files = 'dart_pdf_printing/Sources/dart_pdf_printing/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.frameworks = 'UIKit'
  s.swift_version = '5.0'
end
