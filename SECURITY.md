# Security policy

`dart-pdf` parses untrusted input (arbitrary PDF files) and implements the
cryptography used for encrypted documents and digital signatures: RC4,
AES-128/256, RSA, ECDSA, and CMS. We take security reports seriously.

## Preventing accidental disclosure

This repository and its Actions artifacts are public. Keep credentials in
protected CI secrets or ignored local credential directories. Use placeholders
in documentation, repository-relative editor settings, and synthetic test data.
Do not commit raw terminal traces, debugger URLs, or personal file paths.

The Secret scan workflow runs the checksum-pinned upstream Gitleaks CLI against
the fetched history. To run the same check locally with Gitleaks installed:

```sh
gitleaks git . --log-opts="--all" --redact=100 --no-banner
```

The configuration accepts only three exact, deliberately public signing-test
keys at their fixture paths. Do not replace these exceptions with whole-file
allowlists. A different private key in either fixture must fail the check.

GitHub's console masking does not scrub files uploaded as artifacts. Storeflight
jobs sanitize their text state before upload and require that step to succeed.
Keep credential-bearing job environment names covered by
`tool/storeflight/sanitize_diagnostics.py` and its regression tests. Exclude
private tooling checkouts, credential directories, and signing-key files from
artifact globs. Preserve the files needed for release resumes.

If a public artifact exposes sensitive data, retain a verified private recovery
copy before removing the public copy. Rotate any exposed live credential;
deleting the artifact does not invalidate credentials or erase downloaded copies.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's
[**Report a vulnerability**](https://github.com/ben-milanko/dart-pdf/security/advisories/new)
flow (Security → Advisories → Report a vulnerability), which opens a
confidential advisory visible only to the maintainers.

If you cannot use GitHub advisories, email **ben.milanko@protonmail.com**
with the details.

Please include:

- the affected package(s) and version(s),
- a description of the issue and its impact,
- a minimal PDF or code sample that reproduces it (a crafted file is ideal),
  and
- any suggested remediation.

We aim to acknowledge a report within **7 days** and to provide an initial
assessment within **14 days**. Once a fix is ready we will coordinate a
release and credit you in the advisory unless you prefer to remain
anonymous.

## Scope

Issues we consider security-relevant include:

- memory-unsafe or unbounded behaviour while parsing a crafted file
  (uncontrolled recursion, allocation blow-ups, infinite loops / hangs,
  or crashes that a hostile document can trigger);
- incorrect cryptographic behaviour: decryption, signature *validation*
  that accepts a forged or tampered document, or weaknesses in the
  RC4/AES/RSA/ECDSA/CMS primitives;
- path or resource issues reachable from document content.

Out of scope:

- the example app and its platform shells,
- test fixtures, corpora, and tooling under `tool/`,
- denial of service that requires an already-trusted, cooperating input
  pipeline.

Because the parser is *intentionally lenient* on malformed input
(real-world PDFs are broken), "this broken file does not parse the way
another viewer parses it" is a correctness bug, not a vulnerability. Please
file those as normal issues.

## Supported versions

The project is pre-1.0; security fixes land on `main` and in the latest
published release of each package. There is no long-term support branch
yet.
