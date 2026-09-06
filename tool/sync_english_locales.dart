// Keep the full AU/GB bundles in sync with the US-English templates.
// Run without arguments to check (CI), or --write before flutter gen-l10n.
import 'dart:convert';
import 'dart:io';

const englishBundles = [
  'app/lib/l10n/app',
  'packages/dart_pdf_editor/lib/l10n/dart_pdf_editor',
  'packages/dart_pdf_editor/example/lib/l10n/app',
];

// Reviewed spelling pairs, including inflections. These are whole words, never
// API names or substring rules (-ize cannot safely become -ise everywhere).
// Add pairs here when introducing new UI vocabulary. Context-dependent terms
// such as license/licence, practice/practise and meter/metre need manual review.
const englishSpellingPairs = {
  'color': 'colour',
  'colors': 'colours',
  'colored': 'coloured',
  'coloring': 'colouring',
  'colorful': 'colourful',
  'recolor': 'recolour',
  'recolored': 'recoloured',
  'recoloring': 'recolouring',
  'center': 'centre',
  'centers': 'centres',
  'centered': 'centred',
  'centering': 'centring',
  'gray': 'grey',
  'grayscale': 'greyscale',
  'optimize': 'optimise',
  'optimizes': 'optimises',
  'optimized': 'optimised',
  'optimizing': 'optimising',
  'optimization': 'optimisation',
  'optimizations': 'optimisations',
  'organize': 'organise',
  'organizes': 'organises',
  'organized': 'organised',
  'organizing': 'organising',
  'organization': 'organisation',
  'organizations': 'organisations',
  'recognize': 'recognise',
  'recognizes': 'recognises',
  'recognized': 'recognised',
  'recognizing': 'recognising',
  'initialize': 'initialise',
  'initializes': 'initialises',
  'initialized': 'initialised',
  'initializing': 'initialising',
  'initialization': 'initialisation',
  'customize': 'customise',
  'customizes': 'customises',
  'customized': 'customised',
  'customizing': 'customising',
  'customization': 'customisation',
  'analyze': 'analyse',
  'analyzes': 'analyses',
  'analyzed': 'analysed',
  'analyzing': 'analysing',
  'canceled': 'cancelled',
  'canceling': 'cancelling',
  'labeled': 'labelled',
  'labeling': 'labelling',
  'behavior': 'behaviour',
  'behaviors': 'behaviours',
  'favorite': 'favourite',
  'favorites': 'favourites',
};

String englishMessage(String message, {required bool british}) {
  final pairs = british
      ? englishSpellingPairs
      : {for (final e in englishSpellingPairs.entries) e.value: e.key};
  return _mapMessage(
      message,
      (text) => text.replaceAllMapped(
            RegExp(r'\b[A-Za-z]+\b'),
            (match) {
              final word = match[0]!;
              final replacement = pairs[word.toLowerCase()];
              if (replacement == null) return word;
              if (word == word.toUpperCase()) return replacement.toUpperCase();
              if (word[0] == word[0].toUpperCase()) {
                return '${replacement[0].toUpperCase()}${replacement.substring(1)}';
              }
              return replacement;
            },
          ));
}

// Walk ICU message text, preserving argument names, formats and select keys.
// A regex over the entire message could silently rename {color}, or miss a
// one-word plural body such as one{Color}. gen-l10n validates ICU structure.
String _mapMessage(String message, String Function(String) mapText) {
  final result = StringBuffer();
  var start = 0;
  while (true) {
    final open = message.indexOf('{', start);
    if (open < 0) {
      result.write(mapText(message.substring(start)));
      return result.toString();
    }
    result.write(mapText(message.substring(start, open)));
    final close = _closingBrace(message, open);
    final inner = message.substring(open + 1, close);
    final branch = RegExp(r'^\s*\w+\s*,\s*(plural|select|selectordinal)\s*,')
        .firstMatch(inner);
    if (branch == null) {
      result.write(message.substring(open, close + 1));
    } else {
      result.write('{${inner.substring(0, branch.end)}');
      var position = branch.end;
      while (true) {
        final bodyOpen = inner.indexOf('{', position);
        if (bodyOpen < 0) {
          result.write(inner.substring(position));
          break;
        }
        final bodyClose = _closingBrace(inner, bodyOpen);
        result.write(inner.substring(position, bodyOpen + 1));
        result.write(
            _mapMessage(inner.substring(bodyOpen + 1, bodyClose), mapText));
        result.write('}');
        position = bodyClose + 1;
      }
      result.write('}');
    }
    start = close + 1;
  }
}

int _closingBrace(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}' && --depth == 0) return i;
  }
  throw FormatException('Unbalanced ICU message', text, open);
}

void main(List<String> args) {
  if (args.any((arg) => arg != '--write')) {
    stderr.writeln('Usage: dart tool/sync_english_locales.dart [--write]');
    exitCode = 64;
    return;
  }
  final write = args.contains('--write');
  final problems = <String>[];
  var messages = 0;
  for (final bundle in englishBundles) {
    final template = jsonDecode(File('${bundle}_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final regional = <String, String>{};
    for (final entry in template.entries) {
      if (entry.key.startsWith('@')) continue;
      final message = entry.value as String;
      if (englishMessage(message, british: false) != message) {
        problems.add('${bundle}_en.arb: ${entry.key} uses a UK/AU spelling; '
            'the base English template uses US spellings.');
      }
      regional[entry.key] = englishMessage(message, british: true);
      messages++;
    }
    for (final locale in ['en_AU', 'en_GB']) {
      final file = File('${bundle}_$locale.arb');
      final expected = <String, dynamic>{'@@locale': locale, ...regional};
      if (write) {
        file.writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(expected)}\n');
        continue;
      }
      if (!file.existsSync()) {
        problems.add('${file.path}: missing regional bundle');
        continue;
      }
      final actual =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in expected.entries) {
        if (actual[entry.key] != entry.value) {
          problems.add('${file.path}: ${entry.key} is out of sync');
        }
      }
      for (final key in actual.keys) {
        if (!key.startsWith('@') && !expected.containsKey(key)) {
          problems.add('${file.path}: obsolete key $key');
        }
      }
    }
  }
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    stderr.writeln('Fix the template spellings, then run '
        'dart tool/sync_english_locales.dart --write and flutter gen-l10n '
        'in each bundle.');
    exitCode = 1;
  } else {
    stdout.writeln('English regions ${write ? 'updated' : 'OK'}: '
        '$messages messages across ${englishBundles.length} bundles.');
  }
}
