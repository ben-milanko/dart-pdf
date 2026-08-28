// PLACEHOLDER - not the real render worker.
//
// The real worker is a ~1 MB `dart compile js` bundle that links most of the
// stack, so almost every source change regenerated it. Committing that blob
// churned nearly every PR, made two open PRs unmergeable (two dart2js outputs
// cannot merge textually), and its `.js.deps` sibling leaked absolute local
// paths. So the real bundle is NO LONGER committed (issue #582); it is
// generated at the points that actually serve it to the web:
//
//   * publishing         - tool/release.sh runs `build_web_worker` before
//                          `pub publish`, so the pub.dev archive ships the real
//                          worker;
//   * web deploy/preview  - the deploy/preview/release-web workflows already run
//                          `build_web_worker --out .../pdf_render_worker.dart.js`
//                          before `flutter build web`;
//   * local web builds    - app/tool/build_web.sh regenerates it first.
//
// This tiny, STABLE placeholder stays committed only so the file DECLARED under
// `flutter: assets:` in pubspec.yaml always exists: `dart analyze` and every
// `flutter build` (web AND native - Flutter bundles a package's declared assets
// on every target) fail on a missing declared asset. A ~1 KB placeholder that
// never changes keeps them green with none of the churn/merge/`.deps` problems.
//
// On the web this placeholder throws on load, so the client's worker `onerror`
// handler (render_worker_web.dart) falls back to main-thread rendering - the
// same graceful degradation as a missing worker URL - until the real bundle is
// generated. A CI guard keeps this file small so the real bundle is never
// committed by accident. See doc/render_worker_web.md.
throw new Error(
  'dart_pdf_editor web render worker not built - this is the committed ' +
  'placeholder (issue #582). Generate the real bundle with `dart run ' +
  'dart_pdf_editor:build_web_worker` (or app/tool/build_web.sh); web ' +
  'rendering falls back to the main thread until then.',
);
