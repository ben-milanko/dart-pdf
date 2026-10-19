// One-release coordination authorized by Ben: preserve the draft, release
// 10.0.0, then start the test against the released version. Ben subsequently
// authorized completing the SDK-26 rebuild after Apple rejected the old IPA.
// Never merge this
// operational branch into main or change the tracked protection policy.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  assert.equal(process.env.COORDINATED_RESUME_RUN, '39207384278');
  assert.equal(process.env.COORDINATED_FROM_STEP, 'build.ios');
  assert.equal(process.env.COORDINATED_PLATFORMS, 'ios');
  assert.equal(process.env.COORDINATED_DESTINATIONS, 'apple');
  assert.equal(process.env.COORDINATED_UNTIL, 'review');
  assert.equal(process.env.COORDINATED_DRY_RUN, 'false');
  assert.match(fs.readFileSync('app/pubspec.yaml', 'utf8'), /^version: 10\.0\.0\+47$/m);
  const ledger = JSON.parse(fs.readFileSync('app/.storeflight/releases/4c821351e13e8ca45aac5e02.json'));
  assert.equal(ledger.source_sha, 'f5542de1e1316c45a5ce081f0302760eb21f54d7');
  assert.equal(ledger.group_id, '812c631ae23a594aa279');
  assert.equal(ledger.version, '10.0.0+47');
  assert.equal(ledger.steps['build.ios'].status, 'succeeded');
  const digest = 'a50053859430ef3a99c83a0e2e8b1cf7526b0a4d156119140aaacc06db3732cd';
  assert.equal(ledger.artifacts.ios.sha256, digest);
  const artifact = [path.resolve('app', ledger.artifacts.ios.relative_path),
    path.resolve('app/build/ios/ipa/DartPDF.ipa')].find(p => fs.existsSync(p));
  assert.ok(artifact, 'Restore the rejected IPA to verify the original build provenance');
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(artifact)).digest('hex'), digest);

  const encode = x => Buffer.from(JSON.stringify(x)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({alg: 'ES256', kid: process.env.ASC_API_KEY_ID, typ: 'JWT'})}.${encode({iss: process.env.ASC_API_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'})}`;
  const signature = crypto.sign('sha256', Buffer.from(unsigned), {
    key: process.env.ASC_API_KEY_P8, dsaEncoding: 'ieee-p1363'
  }).toString('base64url');
  const headers = {Authorization: `Bearer ${unsigned}.${signature}`};
  async function inventory(url) {
    const rows = [];
    const included = [];
    const visited = new Set();
    while (url) {
      assert.equal(new URL(url).origin, 'https://api.appstoreconnect.apple.com');
      assert.ok(!visited.has(url));
      visited.add(url);
      const response = await fetch(url, {headers, signal: AbortSignal.timeout(30000)});
      assert.ok(response.ok, `Apple inventory HTTP ${response.status}`);
      const page = await response.json();
      rows.push(...page.data);
      included.push(...(page.included || []));
      url = page.links?.next;
    }
    return {rows, included};
  }
  const nativeBuilds = await inventory('https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6780083686&filter[version]=47&include=preReleaseVersion&limit=200');
  for (const build of nativeBuilds.rows) {
    const preReleaseId = build.relationships?.preReleaseVersion?.data?.id;
    const preRelease = nativeBuilds.included.find(x => x.type === 'preReleaseVersions' && x.id === preReleaseId);
    assert.ok(preRelease, 'Every build must have a known platform');
    assert.notEqual(preRelease.attributes.platform, 'IOS', 'An iOS build 47 already exists; reconcile it instead of rebuilding');
  }
  const versions = await inventory('https://api.appstoreconnect.apple.com/v1/apps/6780083686/appStoreVersions?filter[platform]=IOS&filter[versionString]=10.0.0&limit=200');
  assert.equal(versions.rows.length, 0, 'An iOS 10.0.0 version already exists; reconcile its submission first');
  const tests = [];
  let url = 'https://api.appstoreconnect.apple.com/v1/apps/6780083686/appStoreVersionExperimentsV2?limit=200';
  const visited = new Set();
  while (url) {
    assert.equal(new URL(url).origin, 'https://api.appstoreconnect.apple.com');
    assert.ok(!visited.has(url));
    visited.add(url);
    const response = await fetch(url, {headers, signal: AbortSignal.timeout(30000)});
    assert.ok(response.ok, `Experiment inventory HTTP ${response.status}`);
    const page = await response.json();
    tests.push(...page.data);
    url = page.links?.next;
  }
  const unfinished = tests.filter(t => !['STOPPED', 'COMPLETED'].includes(t.attributes.state));
  assert.equal(unfinished.length, 1, 'Only the specifically coordinated draft is allowed');
  assert.equal(unfinished[0].id, 'd5106e8d-6034-4c91-a916-1feb10749014');
  assert.deepEqual(unfinished[0].attributes, {
    name: 'iOS English screenshot order 2026-10', platform: 'IOS',
    trafficProportion: 50, state: 'PREPARE_FOR_SUBMISSION', reviewRequired: true,
    startDate: null, endDate: null
  });
  const source = fs.readFileSync('storeflight.yaml', 'utf8');
  assert.equal(source.split('protect_product_page_tests: true').length, 2);
  assert.match(source, /release_listing_policy: preserve/);
  const target = path.resolve('.storeflight-ios-coordinated.yaml');
  fs.writeFileSync(target, source.replace('protect_product_page_tests: true', 'protect_product_page_tests: false'), {mode: 0o600});
  fs.appendFileSync(process.env.GITHUB_ENV, `STOREFLIGHT_CONFIG=${target}\n`);
  fs.writeFileSync(path.join(process.env.RUNNER_TEMP, 'ios-experiment-preserved-before.json'), JSON.stringify({checkedAt: new Date().toISOString(), tests}, null, 2));
  console.log('Coordinated iOS 10.0.0 SDK-26 rebuild: rejected IPA provenance verified; no accepted iOS build; exact draft preserved; tracked protection unchanged.');
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
