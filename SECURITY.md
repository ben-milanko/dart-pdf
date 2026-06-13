# Security Policy

`dart-pdf` parses untrusted input (arbitrary PDF files) and implements
cryptography — RC4, AES-128/256, RSA, ECDSA, CMS — for encrypted documents
and digital signatures. We take security reports seriously.

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
- a minimal PDF or code sample that reproduces it (a crafted file is
  ideal — see below), and
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
another viewer parses it" is a correctness bug, not a vulnerability —
please file those as normal issues.

## Supported versions

The project is pre-1.0; security fixes land on `main` and in the latest
published release of each package. There is no long-term support branch
yet.
