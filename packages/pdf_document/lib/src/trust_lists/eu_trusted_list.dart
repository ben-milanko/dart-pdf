/// The EU trusted lists (eIDAS Art. 22, ETSI TS 119 612): the Commission's
/// List of Trusted Lists (LOTL) and the Member State lists it points to,
/// fetched through a host transport, signature-verified, and reduced to the
/// qualified CA certificates a PDF signature can chain to.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import '../signature.dart';
import 'xml_dsig.dart';
import 'xml_lite.dart';

/// Downloads [url] and returns the body; throws on failure. The host's
/// transport (the library performs no I/O).
typedef PdfTrustListFetch = Future<Uint8List> Function(Uri url);

/// The EU LOTL location and the certificates allowed to sign it.
abstract final class PdfEuLotl {
  /// Where the Commission publishes the LOTL.
  static final url = Uri.parse('https://ec.europa.eu/tools/lotl/eu-lotl.xml');

  /// SHA-256 fingerprints of the certificates allowed to sign the LOTL,
  /// taken from the LOTL's pointer to itself (sequence 394, issued
  /// 2026-09-10). The Commission announces these in the Official Journal of
  /// the EU (most recently for the TL v6 transition in April 2026); a LOTL
  /// signed by any other certificate is refused. When a new announcement
  /// lands, cross-check it and update this set - see
  /// doc/signing-identities.md.
  static const signerFingerprints = {
    'd2064fdd70f6982dcc516b86d9d5c56aea939417c624b2e478c0b29de54f8474',
    'e0a620fbb6747362bb933ac44169d676a553444716cf5f31605f12a22b8396b1',
    'c0641c4f7d56c431b1c924742db7fce9c1eef7d7fd212113a2768486b3abcdc5',
    'df7e29360c34b2b8d6d5f40325c1d4d12c9922cecd33b7407674a74b2b3ca1e5',
    'b63d416744e7098bf9ec2caa596a93bc2468e37f8284ba65ecc061711bcbaa18',
    '236103f03a8031ae8f47f9059bf8de38564cdbfebedde4a597d50f8980aa653b',
  };
}

/// ETSI service types kept as signature trust anchors.
const _anchorServiceTypes = {
  'http://uri.etsi.org/TrstSvc/Svctype/CA/QC',
  'http://uri.etsi.org/TrstSvc/Svctype/NationalRootCA-QC',
};

/// Service statuses that mean "currently trusted" (TL v5/v6, plus the
/// pre-eIDAS names some lists still carry).
const _activeStatuses = {
  'http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted',
  'http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/recognisedatnationallevel',
  'http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/undersupervision',
  'http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/accredited',
  'http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/supervisionincessation',
};

/// A pointer in the LOTL to one Member State's list.
class PdfTrustListPointer {
  PdfTrustListPointer(this.territory, this.location, this.signers);

  /// ISO 3166 country code (e.g. `DE`).
  final String territory;
  final Uri location;

  /// The certificates allowed to sign that list.
  final List<X509Certificate> signers;
}

/// One qualified CA service certificate from a Member State list.
class PdfTrustListEntry {
  PdfTrustListEntry({
    required this.territory,
    required this.serviceName,
    required this.serviceType,
    required this.certificate,
  });

  final String territory;
  final String serviceName;
  final String serviceType;

  /// DER.
  final Uint8List certificate;
}

/// A verified set of EU trust anchors, with the per-list problems met while
/// building it.
class PdfEuTrustListSnapshot {
  PdfEuTrustListSnapshot({
    required this.entries,
    required this.fetchedAt,
    this.lotlSequenceNumber,
    this.lotlIssued,
    this.lotlNextUpdate,
    this.problems = const {},
  });

  final List<PdfTrustListEntry> entries;
  final DateTime fetchedAt;
  final int? lotlSequenceNumber;
  final DateTime? lotlIssued;
  final DateTime? lotlNextUpdate;

  /// Territory (or `EU` for the LOTL) -> why that list was skipped.
  final Map<String, String> problems;

  /// A trust store anchored at every entry.
  PdfTrustStore toTrustStore() {
    final store = PdfTrustStore();
    final seen = <String>{};
    for (final e in entries) {
      if (seen.add(base64.encode(e.certificate))) {
        try {
          store.addDer(e.certificate);
        } on Object {
          // an unparsable certificate is not an anchor
        }
      }
    }
    return store;
  }

  /// A PEM bundle with provenance comments - the cache / hand-off format
  /// [PdfEuTrustListSnapshot.fromPem] and `PdfTrustStore.addPem` read.
  String toPem() {
    final out = StringBuffer()
      ..writeln('# EU trusted list anchors (qualified CA services)')
      ..writeln('# fetched-at: ${fetchedAt.toUtc().toIso8601String()}');
    if (lotlSequenceNumber != null) {
      out.writeln('# lotl-sequence: $lotlSequenceNumber');
    }
    if (lotlIssued != null) {
      out.writeln('# lotl-issued: ${lotlIssued!.toUtc().toIso8601String()}');
    }
    if (lotlNextUpdate != null) {
      out.writeln(
          '# lotl-next-update: ${lotlNextUpdate!.toUtc().toIso8601String()}');
    }
    for (final entry in problems.entries) {
      out.writeln('# skipped ${entry.key}: '
          '${entry.value.replaceAll('\n', ' ')}');
    }
    for (final e in entries) {
      out
        ..writeln()
        ..writeln('# ${e.territory}: ${e.serviceName.replaceAll('\n', ' ')}')
        ..writeln('# type: ${e.serviceType}')
        ..write(pemEncode('CERTIFICATE', e.certificate));
    }
    return out.toString();
  }

  /// Reads a [toPem] bundle back.
  factory PdfEuTrustListSnapshot.fromPem(String pem) {
    DateTime? header(String key) {
      final m = RegExp('^# $key: (.+)\$', multiLine: true).firstMatch(pem);
      return m == null ? null : DateTime.tryParse(m.group(1)!.trim());
    }

    final entries = <PdfTrustListEntry>[];
    final block = RegExp(r'# ([A-Z]{2}|EU): ([^\n]*)\n# type: ([^\n]*)\n'
        r'(-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----)');
    for (final m in block.allMatches(pem)) {
      entries.add(PdfTrustListEntry(
        territory: m.group(1)!,
        serviceName: m.group(2)!,
        serviceType: m.group(3)!,
        certificate: pemBytes(m.group(4)!),
      ));
    }
    final seq =
        RegExp(r'^# lotl-sequence: (\d+)', multiLine: true).firstMatch(pem);
    return PdfEuTrustListSnapshot(
      entries: entries,
      fetchedAt: header('fetched-at') ?? DateTime.utc(1970),
      lotlSequenceNumber: seq == null ? null : int.parse(seq.group(1)!),
      lotlIssued: header('lotl-issued'),
      lotlNextUpdate: header('lotl-next-update'),
    );
  }
}

String _fingerprint(Uint8List der) => crypto.sha256.convert(der).toString();

/// Parses and verifies the LOTL: its signature must verify and its signing
/// certificate must be one of [pinnedSigners] (SHA-256 fingerprints).
/// Returns the pointers to the Member State XML lists.
({
  List<PdfTrustListPointer> pointers,
  int? sequence,
  DateTime? issued,
  DateTime? nextUpdate
}) parseEuLotl(Uint8List bytes,
    {Set<String> pinnedSigners = PdfEuLotl.signerFingerprints}) {
  final doc = XmlLiteDocument.parse(bytes);
  final check = verifyEnvelopedXmlSignature(doc);
  if (!check.valid) {
    throw FormatException('LOTL signature is invalid: ${check.problems}');
  }
  if (!pinnedSigners.contains(_fingerprint(check.signer!.der))) {
    throw const FormatException(
        'LOTL is signed by a certificate outside the pinned LOTL signers');
  }
  final scheme = doc.root.child('SchemeInformation');
  final pointers = <PdfTrustListPointer>[];
  for (final p in scheme
          ?.child('PointersToOtherTSL')
          ?.childrenNamed('OtherTSLPointer') ??
      const <XmlLiteElement>[]) {
    final location = p.child('TSLLocation')?.text.trim() ?? '';
    final territory =
        p.descendantsNamed('SchemeTerritory').firstOrNull?.text.trim() ?? '';
    final mime = p.descendantsNamed('MimeType').firstOrNull?.text.trim() ?? '';
    final uri = Uri.tryParse(location);
    if (uri == null || territory.isEmpty || territory == 'EU') continue;
    final isXml = mime.contains('xml') ||
        (mime.isEmpty &&
            (location.endsWith('.xml') || location.endsWith('.xtsl')));
    if (!isXml) continue;
    final signers = <X509Certificate>[];
    for (final c in p.descendantsNamed('X509Certificate')) {
      try {
        signers.add(X509Certificate.parse(
            base64.decode(c.text.replaceAll(RegExp(r'\s'), ''))));
      } on Object {
        // skip a malformed pointer certificate
      }
    }
    pointers.add(PdfTrustListPointer(territory, uri, signers));
  }
  return (
    pointers: pointers,
    sequence:
        int.tryParse(scheme?.child('TSLSequenceNumber')?.text.trim() ?? ''),
    issued: DateTime.tryParse(
        scheme?.child('ListIssueDateTime')?.text.trim() ?? ''),
    nextUpdate: DateTime.tryParse(
        scheme?.child('NextUpdate')?.child('dateTime')?.text.trim() ?? ''),
  );
}

/// Parses and verifies one Member State list against its LOTL [pointer]:
/// the list's signature must verify with one of the pointer's certificates.
/// Returns the active qualified CA service certificates.
List<PdfTrustListEntry> parseEuTrustedList(
    Uint8List bytes, PdfTrustListPointer pointer) {
  final doc = XmlLiteDocument.parse(bytes);
  final check = verifyEnvelopedXmlSignature(doc);
  if (!check.valid) {
    throw FormatException('signature is invalid: ${check.problems}');
  }
  final signer = _fingerprint(check.signer!.der);
  if (!pointer.signers.any((c) => _fingerprint(c.der) == signer)) {
    throw const FormatException(
        'signed by a certificate the LOTL does not list for this territory');
  }
  final entries = <PdfTrustListEntry>[];
  for (final service in doc.root.descendantsNamed('TSPService')) {
    final info = service.child('ServiceInformation');
    if (info == null) continue;
    final type = info.child('ServiceTypeIdentifier')?.text.trim() ?? '';
    final status = info.child('ServiceStatus')?.text.trim() ?? '';
    if (!_anchorServiceTypes.contains(type) ||
        !_activeStatuses.contains(status)) {
      continue;
    }
    final name = info
            .child('ServiceName')
            ?.childrenNamed('Name')
            .map((n) => n.text.trim())
            .firstOrNull ??
        '';
    for (final c in info
            .child('ServiceDigitalIdentity')
            ?.descendantsNamed('X509Certificate') ??
        const <XmlLiteElement>[]) {
      try {
        final der = base64.decode(c.text.replaceAll(RegExp(r'\s'), ''));
        X509Certificate.parse(der); // keep only parsable certificates
        entries.add(PdfTrustListEntry(
          territory: pointer.territory,
          serviceName: name,
          serviceType: type,
          certificate: der,
        ));
      } on Object {
        // skip a malformed service certificate
      }
    }
  }
  return entries;
}

/// Fetches the LOTL and every Member State list through [fetch], verifies
/// each signature (the LOTL against [pinnedSigners], each national list
/// against the certificates the LOTL names for it) and collects the
/// qualified CA anchors. A list that fails to download or verify is
/// skipped and reported in [PdfEuTrustListSnapshot.problems]; a LOTL that
/// fails is fatal (thrown).
Future<PdfEuTrustListSnapshot> fetchEuTrustedLists({
  required PdfTrustListFetch fetch,
  Set<String> pinnedSigners = PdfEuLotl.signerFingerprints,
  DateTime? now,
}) async {
  final lotl =
      parseEuLotl(await fetch(PdfEuLotl.url), pinnedSigners: pinnedSigners);
  // One list per territory (the first XML pointer), fetched concurrently -
  // the downloads dominate, and the lists are independent.
  final byTerritory = <String, PdfTrustListPointer>{};
  for (final pointer in lotl.pointers) {
    byTerritory.putIfAbsent(pointer.territory, () => pointer);
  }
  final problems = <String, String>{};
  final results = await Future.wait([
    for (final pointer in byTerritory.values)
      () async {
        try {
          return parseEuTrustedList(await fetch(pointer.location), pointer);
        } on Object catch (e) {
          problems[pointer.territory] = '${pointer.location}: $e';
          return const <PdfTrustListEntry>[];
        }
      }(),
  ]);
  final entries = [for (final list in results) ...list];
  return PdfEuTrustListSnapshot(
    entries: entries,
    fetchedAt: (now ?? DateTime.now()).toUtc(),
    lotlSequenceNumber: lotl.sequence,
    lotlIssued: lotl.issued,
    lotlNextUpdate: lotl.nextUpdate,
    problems: problems,
  );
}
