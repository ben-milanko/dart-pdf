/// Glyph-name tables for simple-font encodings (ISO 32000-1 Annex D).
library;

/// WinAnsiEncoding (cp1252) code → glyph name. Codes 32–126 match
/// StandardEncoding's ASCII range, which is what matters for the common
/// /Encoding values; Standard-vs-WinAnsi differences above 127 are accepted
/// as approximation.
String? winAnsiGlyphName(int code) {
  if (code >= 32 && code <= 126) return _ascii[code - 32];
  return _high[code];
}

/// StandardEncoding high-byte glyph names. ASCII codes are left to the
/// literal fallback so common apostrophes/backticks stay stable.
String? standardGlyphName(int code) => _standardHigh[code];

/// Unicode value for common Adobe glyph names.
int? glyphNameUnicode(String name) => _glyphNameUnicode[name];

/// Built-in ZapfDingbatsEncoding code → Unicode value.
int? zapfDingbatsUnicode(int code) => _zapfDingbats[code];

/// Built-in SymbolEncoding code → Unicode value (ISO 32000-1 Annex D.5).
int? symbolUnicode(int code) => _symbol[code];

const _ascii = [
  'space',
  'exclam',
  'quotedbl',
  'numbersign',
  'dollar',
  'percent',
  'ampersand',
  'quotesingle',
  'parenleft',
  'parenright',
  'asterisk',
  'plus',
  'comma',
  'hyphen',
  'period',
  'slash',
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'colon',
  'semicolon',
  'less',
  'equal',
  'greater',
  'question',
  'at',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
  'bracketleft',
  'backslash',
  'bracketright',
  'asciicircum',
  'underscore',
  'grave',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
  'braceleft',
  'bar',
  'braceright',
  'asciitilde',
];

const _high = <int, String>{
  0x80: 'Euro',
  0x82: 'quotesinglbase',
  0x83: 'florin',
  0x84: 'quotedblbase',
  0x85: 'ellipsis',
  0x86: 'dagger',
  0x87: 'daggerdbl',
  0x88: 'circumflex',
  0x89: 'perthousand',
  0x8A: 'Scaron',
  0x8B: 'guilsinglleft',
  0x8C: 'OE',
  0x8E: 'Zcaron',
  0x91: 'quoteleft',
  0x92: 'quoteright',
  0x93: 'quotedblleft',
  0x94: 'quotedblright',
  0x95: 'bullet',
  0x96: 'endash',
  0x97: 'emdash',
  0x98: 'tilde',
  0x99: 'trademark',
  0x9A: 'scaron',
  0x9B: 'guilsinglright',
  0x9C: 'oe',
  0x9E: 'zcaron',
  0x9F: 'Ydieresis',
  0xA0: 'space',
  0xA1: 'exclamdown',
  0xA2: 'cent',
  0xA3: 'sterling',
  0xA4: 'currency',
  0xA5: 'yen',
  0xA6: 'brokenbar',
  0xA7: 'section',
  0xA8: 'dieresis',
  0xA9: 'copyright',
  0xAA: 'ordfeminine',
  0xAB: 'guillemotleft',
  0xAC: 'logicalnot',
  0xAD: 'hyphen',
  0xAE: 'registered',
  0xAF: 'macron',
  0xB0: 'degree',
  0xB1: 'plusminus',
  0xB2: 'twosuperior',
  0xB3: 'threesuperior',
  0xB4: 'acute',
  0xB5: 'mu',
  0xB6: 'paragraph',
  0xB7: 'periodcentered',
  0xB8: 'cedilla',
  0xB9: 'onesuperior',
  0xBA: 'ordmasculine',
  0xBB: 'guillemotright',
  0xBC: 'onequarter',
  0xBD: 'onehalf',
  0xBE: 'threequarters',
  0xBF: 'questiondown',
  0xC0: 'Agrave',
  0xC1: 'Aacute',
  0xC2: 'Acircumflex',
  0xC3: 'Atilde',
  0xC4: 'Adieresis',
  0xC5: 'Aring',
  0xC6: 'AE',
  0xC7: 'Ccedilla',
  0xC8: 'Egrave',
  0xC9: 'Eacute',
  0xCA: 'Ecircumflex',
  0xCB: 'Edieresis',
  0xCC: 'Igrave',
  0xCD: 'Iacute',
  0xCE: 'Icircumflex',
  0xCF: 'Idieresis',
  0xD0: 'Eth',
  0xD1: 'Ntilde',
  0xD2: 'Ograve',
  0xD3: 'Oacute',
  0xD4: 'Ocircumflex',
  0xD5: 'Otilde',
  0xD6: 'Odieresis',
  0xD7: 'multiply',
  0xD8: 'Oslash',
  0xD9: 'Ugrave',
  0xDA: 'Uacute',
  0xDB: 'Ucircumflex',
  0xDC: 'Udieresis',
  0xDD: 'Yacute',
  0xDE: 'Thorn',
  0xDF: 'germandbls',
  0xE0: 'agrave',
  0xE1: 'aacute',
  0xE2: 'acircumflex',
  0xE3: 'atilde',
  0xE4: 'adieresis',
  0xE5: 'aring',
  0xE6: 'ae',
  0xE7: 'ccedilla',
  0xE8: 'egrave',
  0xE9: 'eacute',
  0xEA: 'ecircumflex',
  0xEB: 'edieresis',
  0xEC: 'igrave',
  0xED: 'iacute',
  0xEE: 'icircumflex',
  0xEF: 'idieresis',
  0xF0: 'eth',
  0xF1: 'ntilde',
  0xF2: 'ograve',
  0xF3: 'oacute',
  0xF4: 'ocircumflex',
  0xF5: 'otilde',
  0xF6: 'odieresis',
  0xF7: 'divide',
  0xF8: 'oslash',
  0xF9: 'ugrave',
  0xFA: 'uacute',
  0xFB: 'ucircumflex',
  0xFC: 'udieresis',
  0xFD: 'yacute',
  0xFE: 'thorn',
  0xFF: 'ydieresis',
};

const _standardHigh = <int, String>{
  0xA1: 'exclamdown',
  0xA2: 'cent',
  0xA3: 'sterling',
  0xA4: 'fraction',
  0xA5: 'yen',
  0xA6: 'florin',
  0xA7: 'section',
  0xA8: 'currency',
  0xA9: 'quotesingle',
  0xAA: 'quotedblleft',
  0xAB: 'guillemotleft',
  0xAC: 'guilsinglleft',
  0xAD: 'guilsinglright',
  0xAE: 'fi',
  0xAF: 'fl',
  0xB1: 'endash',
  0xB2: 'dagger',
  0xB3: 'daggerdbl',
  0xB4: 'periodcentered',
  0xB6: 'paragraph',
  0xB7: 'bullet',
  0xB8: 'quotesinglbase',
  0xB9: 'quotedblbase',
  0xBA: 'quotedblright',
  0xBB: 'guillemotright',
  0xBC: 'ellipsis',
  0xBD: 'perthousand',
  0xBF: 'questiondown',
  0xC1: 'grave',
  0xC2: 'acute',
  0xC3: 'circumflex',
  0xC4: 'tilde',
  0xC5: 'macron',
  0xC6: 'breve',
  0xC7: 'dotaccent',
  0xC8: 'dieresis',
  0xCA: 'ring',
  0xCB: 'cedilla',
  0xCD: 'hungarumlaut',
  0xCE: 'ogonek',
  0xCF: 'caron',
  0xD0: 'emdash',
  0xE1: 'AE',
  0xE3: 'ordfeminine',
  0xE8: 'Lslash',
  0xE9: 'Oslash',
  0xEA: 'OE',
  0xEB: 'ordmasculine',
  0xF1: 'ae',
  0xF5: 'dotlessi',
  0xF8: 'lslash',
  0xF9: 'oslash',
  0xFA: 'oe',
  0xFB: 'germandbls',
};

const _glyphNameUnicode = <String, int>{
  // Symbol-font glyph names (Greek, math operators, arrows, the big
  // delimiter pieces). A /Differences array naming these is an explicit,
  // unambiguous instruction from the document, and it is not confined to
  // the Symbol base font - any font may use these names - so they belong
  // here rather than only in the code-indexed table above.
  'exclam': 0x0021,
  'universal': 0x2200,
  'numbersign': 0x0023,
  'existential': 0x2203,
  'percent': 0x0025,
  'ampersand': 0x0026,
  'suchthat': 0x220B,
  'parenleft': 0x0028,
  'parenright': 0x0029,
  'asteriskmath': 0x2217,
  'plus': 0x002B,
  'comma': 0x002C,
  'period': 0x002E,
  'slash': 0x002F,
  'zero': 0x0030,
  'one': 0x0031,
  'two': 0x0032,
  'three': 0x0033,
  'four': 0x0034,
  'five': 0x0035,
  'six': 0x0036,
  'seven': 0x0037,
  'eight': 0x0038,
  'nine': 0x0039,
  'colon': 0x003A,
  'semicolon': 0x003B,
  'less': 0x003C,
  'equal': 0x003D,
  'greater': 0x003E,
  'question': 0x003F,
  'congruent': 0x2245,
  'Alpha': 0x0391,
  'Beta': 0x0392,
  'Chi': 0x03A7,
  'Delta': 0x0394,
  'Epsilon': 0x0395,
  'Phi': 0x03A6,
  'Gamma': 0x0393,
  'Eta': 0x0397,
  'Iota': 0x0399,
  'theta1': 0x03D1,
  'Kappa': 0x039A,
  'Lambda': 0x039B,
  'Mu': 0x039C,
  'Nu': 0x039D,
  'Omicron': 0x039F,
  'Pi': 0x03A0,
  'Theta': 0x0398,
  'Rho': 0x03A1,
  'Sigma': 0x03A3,
  'Tau': 0x03A4,
  'Upsilon': 0x03A5,
  'sigma1': 0x03C2,
  'Omega': 0x03A9,
  'Xi': 0x039E,
  'Psi': 0x03A8,
  'Zeta': 0x0396,
  'bracketleft': 0x005B,
  'therefore': 0x2234,
  'bracketright': 0x005D,
  'perpendicular': 0x22A5,
  'underscore': 0x005F,
  'radicalex': 0xF8E5,
  'alpha': 0x03B1,
  'beta': 0x03B2,
  'chi': 0x03C7,
  'delta': 0x03B4,
  'epsilon': 0x03B5,
  'phi': 0x03C6,
  'gamma': 0x03B3,
  'eta': 0x03B7,
  'iota': 0x03B9,
  'phi1': 0x03D5,
  'kappa': 0x03BA,
  'lambda': 0x03BB,
  'nu': 0x03BD,
  'omicron': 0x03BF,
  'pi': 0x03C0,
  'theta': 0x03B8,
  'rho': 0x03C1,
  'sigma': 0x03C3,
  'tau': 0x03C4,
  'upsilon': 0x03C5,
  'omega1': 0x03D6,
  'omega': 0x03C9,
  'xi': 0x03BE,
  'psi': 0x03C8,
  'zeta': 0x03B6,
  'braceleft': 0x007B,
  'bar': 0x007C,
  'braceright': 0x007D,
  'similar': 0x223C,
  'Upsilon1': 0x03D2,
  'minute': 0x2032,
  'lessequal': 0x2264,
  'infinity': 0x221E,
  'club': 0x2663,
  'diamond': 0x2666,
  'heart': 0x2665,
  'spade': 0x2660,
  'arrowboth': 0x2194,
  'arrowleft': 0x2190,
  'arrowup': 0x2191,
  'arrowright': 0x2192,
  'arrowdown': 0x2193,
  'second': 0x2033,
  'greaterequal': 0x2265,
  'proportional': 0x221D,
  'partialdiff': 0x2202,
  'notequal': 0x2260,
  'equivalence': 0x2261,
  'approxequal': 0x2248,
  'arrowvertex': 0xF8E6,
  'arrowhorizex': 0xF8E7,
  'carriagereturn': 0x21B5,
  'aleph': 0x2135,
  'Ifraktur': 0x2111,
  'Rfraktur': 0x211C,
  'weierstrass': 0x2118,
  'circlemultiply': 0x2297,
  'circleplus': 0x2295,
  'emptyset': 0x2205,
  'intersection': 0x2229,
  'union': 0x222A,
  'propersuperset': 0x2283,
  'reflexsuperset': 0x2287,
  'notsubset': 0x2284,
  'propersubset': 0x2282,
  'reflexsubset': 0x2286,
  'element': 0x2208,
  'notelement': 0x2209,
  'angle': 0x2220,
  'gradient': 0x2207,
  'registerserif': 0xF6DA,
  'copyrightserif': 0xF6D9,
  'trademarkserif': 0xF6DB,
  'product': 0x220F,
  'radical': 0x221A,
  'dotmath': 0x22C5,
  'logicaland': 0x2227,
  'logicalor': 0x2228,
  'arrowdblboth': 0x21D4,
  'arrowdblleft': 0x21D0,
  'arrowdblup': 0x21D1,
  'arrowdblright': 0x21D2,
  'arrowdbldown': 0x21D3,
  'lozenge': 0x25CA,
  'angleleft': 0x2329,
  'registersans': 0x00AE,
  'copyrightsans': 0x00A9,
  'trademarksans': 0x2122,
  'summation': 0x2211,
  'parenlefttp': 0x239B,
  'parenleftex': 0x239C,
  'parenleftbt': 0x239D,
  'bracketlefttp': 0x23A1,
  'bracketleftex': 0x23A2,
  'bracketleftbt': 0x23A3,
  'bracelefttp': 0x23A7,
  'braceleftmid': 0x23A8,
  'braceleftbt': 0x23A9,
  'braceex': 0x23AA,
  'angleright': 0x232A,
  'integral': 0x222B,
  'integraltp': 0x2320,
  'integralex': 0x23AE,
  'integralbt': 0x2321,
  'parenrighttp': 0x239E,
  'parenrightex': 0x239F,
  'parenrightbt': 0x23A0,
  'bracketrighttp': 0x23A4,
  'bracketrightex': 0x23A5,
  'bracketrightbt': 0x23A6,
  'bracerighttp': 0x23AB,
  'bracerightmid': 0x23AC,
  'bracerightbt': 0x23AD,
  'space': 0x0020,
  // Standalone spacing diacritics (AGL). WinAnsi 0x88/0x98 are 'circumflex'
  // and 'tilde'; the rest appear in Standard/Symbol encodings. Without these
  // a substituted font falls through to the Latin-1 path and renders the C1
  // control code as tofu.
  'quotedbl': 0x0022,
  'quotesingle': 0x0027,
  'grave': 0x0060,
  'circumflex': 0x02C6,
  'tilde': 0x02DC,
  'breve': 0x02D8,
  'dotaccent': 0x02D9,
  'ring': 0x02DA,
  'caron': 0x02C7,
  'hungarumlaut': 0x02DD,
  'ogonek': 0x02DB,
  'exclamdown': 0x00A1,
  'cent': 0x00A2,
  'sterling': 0x00A3,
  'currency': 0x00A4,
  'yen': 0x00A5,
  'brokenbar': 0x00A6,
  'section': 0x00A7,
  'dieresis': 0x00A8,
  'copyright': 0x00A9,
  'ordfeminine': 0x00AA,
  'guillemotleft': 0x00AB,
  'logicalnot': 0x00AC,
  'registered': 0x00AE,
  'macron': 0x00AF,
  'degree': 0x00B0,
  'plusminus': 0x00B1,
  'twosuperior': 0x00B2,
  'threesuperior': 0x00B3,
  'acute': 0x00B4,
  'mu': 0x00B5,
  'paragraph': 0x00B6,
  'periodcentered': 0x00B7,
  'cedilla': 0x00B8,
  'onesuperior': 0x00B9,
  'ordmasculine': 0x00BA,
  'guillemotright': 0x00BB,
  'onequarter': 0x00BC,
  'onehalf': 0x00BD,
  'threequarters': 0x00BE,
  'questiondown': 0x00BF,
  'Agrave': 0x00C0,
  'Aacute': 0x00C1,
  'Acircumflex': 0x00C2,
  'Atilde': 0x00C3,
  'Adieresis': 0x00C4,
  'Aring': 0x00C5,
  'AE': 0x00C6,
  'Ccedilla': 0x00C7,
  'Egrave': 0x00C8,
  'Eacute': 0x00C9,
  'Ecircumflex': 0x00CA,
  'Edieresis': 0x00CB,
  'Igrave': 0x00CC,
  'Iacute': 0x00CD,
  'Icircumflex': 0x00CE,
  'Idieresis': 0x00CF,
  'Eth': 0x00D0,
  'Ntilde': 0x00D1,
  'Ograve': 0x00D2,
  'Oacute': 0x00D3,
  'Ocircumflex': 0x00D4,
  'Otilde': 0x00D5,
  'Odieresis': 0x00D6,
  'multiply': 0x00D7,
  'Oslash': 0x00D8,
  'Ugrave': 0x00D9,
  'Uacute': 0x00DA,
  'Ucircumflex': 0x00DB,
  'Udieresis': 0x00DC,
  'Yacute': 0x00DD,
  'Thorn': 0x00DE,
  'germandbls': 0x00DF,
  'agrave': 0x00E0,
  'aacute': 0x00E1,
  'acircumflex': 0x00E2,
  'atilde': 0x00E3,
  'adieresis': 0x00E4,
  'aring': 0x00E5,
  'ae': 0x00E6,
  'ccedilla': 0x00E7,
  'egrave': 0x00E8,
  'eacute': 0x00E9,
  'ecircumflex': 0x00EA,
  'edieresis': 0x00EB,
  'igrave': 0x00EC,
  'iacute': 0x00ED,
  'icircumflex': 0x00EE,
  'idieresis': 0x00EF,
  'eth': 0x00F0,
  'ntilde': 0x00F1,
  'ograve': 0x00F2,
  'oacute': 0x00F3,
  'ocircumflex': 0x00F4,
  'otilde': 0x00F5,
  'odieresis': 0x00F6,
  'divide': 0x00F7,
  'oslash': 0x00F8,
  'ugrave': 0x00F9,
  'uacute': 0x00FA,
  'ucircumflex': 0x00FB,
  'udieresis': 0x00FC,
  'yacute': 0x00FD,
  'thorn': 0x00FE,
  'ydieresis': 0x00FF,
  'bullet': 0x2022,
  'dagger': 0x2020,
  'daggerdbl': 0x2021,
  'ellipsis': 0x2026,
  'emdash': 0x2014,
  'endash': 0x2013,
  'florin': 0x0192,
  'fraction': 0x2044,
  'guilsinglleft': 0x2039,
  'guilsinglright': 0x203A,
  'minus': 0x2212,
  'perthousand': 0x2030,
  'quotedblbase': 0x201E,
  'quotedblleft': 0x201C,
  'quotedblright': 0x201D,
  'quoteleft': 0x2018,
  'quoteright': 0x2019,
  'quotesinglbase': 0x201A,
  'trademark': 0x2122,
  'fi': 0xFB01,
  'fl': 0xFB02,
  'Lslash': 0x0141,
  'OE': 0x0152,
  'Scaron': 0x0160,
  'Ydieresis': 0x0178,
  'Zcaron': 0x017D,
  'dotlessi': 0x0131,
  'lslash': 0x0142,
  'oe': 0x0153,
  'scaron': 0x0161,
  'zcaron': 0x017E,
  'Euro': 0x20AC,
};

const _zapfDingbats = <int, int>{
  0x21: 0x2701,
  0x22: 0x2702,
  0x23: 0x2703,
  0x24: 0x2704,
  0x25: 0x260E,
  0x26: 0x2706,
  0x27: 0x2707,
  0x28: 0x2708,
  0x29: 0x2709,
  0x2A: 0x261B,
  0x2B: 0x261E,
  0x2C: 0x270C,
  0x2D: 0x270D,
  0x2E: 0x270E,
  0x2F: 0x270F,
  0x30: 0x2710,
  0x31: 0x2711,
  0x32: 0x2712,
  0x33: 0x2713,
  0x34: 0x2714,
  0x35: 0x2715,
  0x36: 0x2716,
  0x37: 0x2717,
  0x38: 0x2718,
  0x39: 0x2719,
  0x3A: 0x271A,
  0x3B: 0x271B,
  0x3C: 0x271C,
  0x3D: 0x271D,
  0x3E: 0x271E,
  0x3F: 0x271F,
  0x40: 0x2720,
  0x41: 0x2721,
  0x42: 0x2722,
  0x43: 0x2723,
  0x44: 0x2724,
  0x45: 0x2725,
  0x46: 0x2726,
  0x47: 0x2727,
  0x48: 0x2605,
  0x49: 0x2729,
  0x4A: 0x272A,
  0x4B: 0x272B,
  0x4C: 0x272C,
  0x4D: 0x272D,
  0x4E: 0x272E,
  0x4F: 0x272F,
  0x50: 0x2730,
  0x51: 0x2731,
  0x52: 0x2732,
  0x53: 0x2733,
  0x54: 0x2734,
  0x55: 0x2735,
  0x56: 0x2736,
  0x57: 0x2737,
  0x58: 0x2738,
  0x59: 0x2739,
  0x5A: 0x273A,
  0x5B: 0x273B,
  0x5C: 0x273C,
  0x5D: 0x273D,
  0x5E: 0x273E,
  0x5F: 0x273F,
  0x60: 0x2740,
  0x61: 0x2741,
  0x62: 0x2742,
  0x63: 0x2743,
  0x64: 0x2744,
  0x65: 0x2745,
  0x66: 0x2746,
  0x67: 0x2747,
  0x68: 0x2748,
  0x69: 0x2749,
  0x6A: 0x274A,
  0x6B: 0x274B,
  0x6C: 0x25CF,
  0x6D: 0x274D,
  0x6E: 0x25A0,
  0x6F: 0x274F,
  0x70: 0x2750,
  0x71: 0x2751,
  0x72: 0x2752,
  0x73: 0x25B2,
  0x74: 0x25BC,
  0x75: 0x25C6,
  0x76: 0x2756,
  0x77: 0x25D7,
  0x78: 0x2758,
  0x79: 0x2759,
  0x7A: 0x275A,
  0x7B: 0x275B,
  0x7C: 0x275C,
  0x7D: 0x275D,
  0x7E: 0x275E,
  0xA1: 0x2761,
  0xA2: 0x2762,
  0xA3: 0x2763,
  0xA4: 0x2764,
  0xA5: 0x2765,
  0xA6: 0x2766,
  0xA7: 0x2767,
  0xA8: 0x2663,
  0xA9: 0x2666,
  0xAA: 0x2665,
  0xAB: 0x2660,
  0xAC: 0x2460,
  0xAD: 0x2461,
  0xAE: 0x2462,
  0xAF: 0x2463,
  0xB0: 0x2464,
  0xB1: 0x2465,
  0xB2: 0x2466,
  0xB3: 0x2467,
  0xB4: 0x2468,
  0xB5: 0x2469,
  0xB6: 0x2776,
  0xB7: 0x2777,
  0xB8: 0x2778,
  0xB9: 0x2779,
  0xBA: 0x277A,
  0xBB: 0x277B,
  0xBC: 0x277C,
  0xBD: 0x277D,
  0xBE: 0x277E,
  0xBF: 0x277F,
  0xC0: 0x2780,
  0xC1: 0x2781,
  0xC2: 0x2782,
  0xC3: 0x2783,
  0xC4: 0x2784,
  0xC5: 0x2785,
  0xC6: 0x2786,
  0xC7: 0x2787,
  0xC8: 0x2788,
  0xC9: 0x2789,
  0xCA: 0x278A,
  0xCB: 0x278B,
  0xCC: 0x278C,
  0xCD: 0x278D,
  0xCE: 0x278E,
  0xCF: 0x278F,
  0xD0: 0x2790,
  0xD1: 0x2791,
  0xD2: 0x2792,
  0xD3: 0x2793,
  0xD4: 0x2794,
  0xD5: 0x2192,
  0xD6: 0x2194,
  0xD7: 0x2195,
  0xD8: 0x2798,
  0xD9: 0x2799,
  0xDA: 0x279A,
  0xDB: 0x279B,
  0xDC: 0x279C,
  0xDD: 0x279D,
  0xDE: 0x279E,
  0xDF: 0x279F,
  0xE0: 0x27A0,
  0xE1: 0x27A1,
  0xE2: 0x27A2,
  0xE3: 0x27A3,
  0xE4: 0x27A4,
  0xE5: 0x27A5,
  0xE6: 0x27A6,
  0xE7: 0x27A7,
  0xE8: 0x27A8,
  0xE9: 0x27A9,
  0xEA: 0x27AA,
  0xEB: 0x27AB,
  0xEC: 0x27AC,
  0xED: 0x27AD,
  0xEE: 0x27AE,
  0xEF: 0x27AF,
  0xF1: 0x27B1,
  0xF2: 0x27B2,
  0xF3: 0x27B3,
  0xF4: 0x27B4,
  0xF5: 0x27B5,
  0xF6: 0x27B6,
  0xF7: 0x27B7,
  0xF8: 0x27B8,
  0xF9: 0x27B9,
  0xFA: 0x27BA,
  0xFB: 0x27BB,
  0xFC: 0x27BC,
  0xFD: 0x27BD,
  0xFE: 0x27BE,
};

/// The first 229 CFF standard strings (SIDs 0–228): .notdef through zcaron.
/// The remaining expert-set strings (through SID 390) are rarely referenced
/// by Differences and resolve to null here.
const cffStandardStrings = [
  '.notdef',
  'space',
  'exclam',
  'quotedbl',
  'numbersign',
  'dollar',
  'percent',
  'ampersand',
  'quoteright',
  ..._asciiTail,
  'exclamdown',
  'cent',
  'sterling',
  'fraction',
  'yen',
  'florin',
  'section',
  'currency',
  'quotesingle',
  'quotedblleft',
  'guillemotleft',
  'guilsinglleft',
  'guilsinglright',
  'fi',
  'fl',
  'endash',
  'dagger',
  'daggerdbl',
  'periodcentered',
  'paragraph',
  'bullet',
  'quotesinglbase',
  'quotedblbase',
  'quotedblright',
  'guillemotright',
  'ellipsis',
  'perthousand',
  'questiondown',
  'grave',
  'acute',
  'circumflex',
  'tilde',
  'macron',
  'breve',
  'dotaccent',
  'dieresis',
  'ring',
  'cedilla',
  'hungarumlaut',
  'ogonek',
  'caron',
  'emdash',
  'AE',
  'ordfeminine',
  'Lslash',
  'Oslash',
  'OE',
  'ordmasculine',
  'ae',
  'dotlessi',
  'lslash',
  'oslash',
  'oe',
  'germandbls',
  'onesuperior',
  'logicalnot',
  'mu',
  'trademark',
  'Eth',
  'onehalf',
  'plusminus',
  'Thorn',
  'onequarter',
  'divide',
  'brokenbar',
  'degree',
  'thorn',
  'threequarters',
  'twosuperior',
  'registered',
  'minus',
  'eth',
  'multiply',
  'threesuperior',
  'copyright',
  'Aacute',
  'Acircumflex',
  'Adieresis',
  'Agrave',
  'Aring',
  'Atilde',
  'Ccedilla',
  'Eacute',
  'Ecircumflex',
  'Edieresis',
  'Egrave',
  'Iacute',
  'Icircumflex',
  'Idieresis',
  'Igrave',
  'Ntilde',
  'Oacute',
  'Ocircumflex',
  'Odieresis',
  'Ograve',
  'Otilde',
  'Scaron',
  'Uacute',
  'Ucircumflex',
  'Udieresis',
  'Ugrave',
  'Yacute',
  'Ydieresis',
  'Zcaron',
  'aacute',
  'acircumflex',
  'adieresis',
  'agrave',
  'aring',
  'atilde',
  'ccedilla',
  'eacute',
  'ecircumflex',
  'edieresis',
  'egrave',
  'iacute',
  'icircumflex',
  'idieresis',
  'igrave',
  'ntilde',
  'oacute',
  'ocircumflex',
  'odieresis',
  'ograve',
  'otilde',
  'scaron',
  'uacute',
  'ucircumflex',
  'udieresis',
  'ugrave',
  'yacute',
  'ydieresis',
  'zcaron',
];

// ASCII names after quotesingle (SID 9 is parenleft): the standard strings
// use 'quoteright' for 0x27 and 'quoteleft' for 0x60, unlike WinAnsi.
const _asciiTail = [
  'parenleft',
  'parenright',
  'asterisk',
  'plus',
  'comma',
  'hyphen',
  'period',
  'slash',
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'colon',
  'semicolon',
  'less',
  'equal',
  'greater',
  'question',
  'at',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
  'bracketleft',
  'backslash',
  'bracketright',
  'asciicircum',
  'underscore',
  'quoteleft',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
  'braceleft',
  'bar',
  'braceright',
  'asciitilde',
];

/// Adobe's built-in Symbol encoding, code → Unicode. Symbol is one of the
/// standard 14 fonts, so a document may select it with no /Encoding and no
/// embedded program; without this table those codes fall through to the
/// Latin-1 approximation and 0x61 renders 'a' instead of alpha.
///
/// Derived from Adobe's own Symbol-to-Unicode mapping, with three deliberate
/// departures where that table's value is unhelpful on a real system font:
///
///  * Greek letters use the Greek block rather than a compatibility duplicate
///    (0x44 Delta → U+0394 not U+2206, 0x57 Omega → U+03A9 not U+2126,
///    0x6D mu → U+03BC not U+00B5), so the whole Greek run is consistent and
///    searching for a typed Greek letter matches.
///  * The "sans" legal marks map to the real characters (0xE2 registersans →
///    U+00AE, 0xE3 → U+00A9, 0xE4 → U+2122) instead of Adobe's private-use
///    code points, which no substituted font carries.
///  * The big-delimiter assembly pieces map to U+239B–U+23AE, the block
///    Unicode added for exactly these glyphs, instead of the private-use
///    values. Same reasoning as the ZapfDingbats ornaments: the private-use
///    code points render as tofu everywhere outside Adobe's own fonts.
///
/// 0x60 radicalex keeps its private-use value: it is a bare overbar extender
/// with no single agreed code point.
const _symbol = <int, int>{
  0x20: 0x0020, // space
  0x21: 0x0021, // exclam
  0x22: 0x2200, // universal
  0x23: 0x0023, // numbersign
  0x24: 0x2203, // existential
  0x25: 0x0025, // percent
  0x26: 0x0026, // ampersand
  0x27: 0x220B, // suchthat
  0x28: 0x0028, // parenleft
  0x29: 0x0029, // parenright
  0x2A: 0x2217, // asteriskmath
  0x2B: 0x002B, // plus
  0x2C: 0x002C, // comma
  0x2D: 0x2212, // minus
  0x2E: 0x002E, // period
  0x2F: 0x002F, // slash
  0x30: 0x0030, // zero
  0x31: 0x0031, // one
  0x32: 0x0032, // two
  0x33: 0x0033, // three
  0x34: 0x0034, // four
  0x35: 0x0035, // five
  0x36: 0x0036, // six
  0x37: 0x0037, // seven
  0x38: 0x0038, // eight
  0x39: 0x0039, // nine
  0x3A: 0x003A, // colon
  0x3B: 0x003B, // semicolon
  0x3C: 0x003C, // less
  0x3D: 0x003D, // equal
  0x3E: 0x003E, // greater
  0x3F: 0x003F, // question
  0x40: 0x2245, // congruent
  0x41: 0x0391, // Alpha
  0x42: 0x0392, // Beta
  0x43: 0x03A7, // Chi
  0x44: 0x0394, // Delta
  0x45: 0x0395, // Epsilon
  0x46: 0x03A6, // Phi
  0x47: 0x0393, // Gamma
  0x48: 0x0397, // Eta
  0x49: 0x0399, // Iota
  0x4A: 0x03D1, // theta1
  0x4B: 0x039A, // Kappa
  0x4C: 0x039B, // Lambda
  0x4D: 0x039C, // Mu
  0x4E: 0x039D, // Nu
  0x4F: 0x039F, // Omicron
  0x50: 0x03A0, // Pi
  0x51: 0x0398, // Theta
  0x52: 0x03A1, // Rho
  0x53: 0x03A3, // Sigma
  0x54: 0x03A4, // Tau
  0x55: 0x03A5, // Upsilon
  0x56: 0x03C2, // sigma1
  0x57: 0x03A9, // Omega
  0x58: 0x039E, // Xi
  0x59: 0x03A8, // Psi
  0x5A: 0x0396, // Zeta
  0x5B: 0x005B, // bracketleft
  0x5C: 0x2234, // therefore
  0x5D: 0x005D, // bracketright
  0x5E: 0x22A5, // perpendicular
  0x5F: 0x005F, // underscore
  0x60: 0xF8E5, // radicalex
  0x61: 0x03B1, // alpha
  0x62: 0x03B2, // beta
  0x63: 0x03C7, // chi
  0x64: 0x03B4, // delta
  0x65: 0x03B5, // epsilon
  0x66: 0x03C6, // phi
  0x67: 0x03B3, // gamma
  0x68: 0x03B7, // eta
  0x69: 0x03B9, // iota
  0x6A: 0x03D5, // phi1
  0x6B: 0x03BA, // kappa
  0x6C: 0x03BB, // lambda
  0x6D: 0x03BC, // mu
  0x6E: 0x03BD, // nu
  0x6F: 0x03BF, // omicron
  0x70: 0x03C0, // pi
  0x71: 0x03B8, // theta
  0x72: 0x03C1, // rho
  0x73: 0x03C3, // sigma
  0x74: 0x03C4, // tau
  0x75: 0x03C5, // upsilon
  0x76: 0x03D6, // omega1
  0x77: 0x03C9, // omega
  0x78: 0x03BE, // xi
  0x79: 0x03C8, // psi
  0x7A: 0x03B6, // zeta
  0x7B: 0x007B, // braceleft
  0x7C: 0x007C, // bar
  0x7D: 0x007D, // braceright
  0x7E: 0x223C, // similar
  0xA0: 0x20AC, // Euro
  0xA1: 0x03D2, // Upsilon1
  0xA2: 0x2032, // minute
  0xA3: 0x2264, // lessequal
  0xA4: 0x2044, // fraction
  0xA5: 0x221E, // infinity
  0xA6: 0x0192, // florin
  0xA7: 0x2663, // club
  0xA8: 0x2666, // diamond
  0xA9: 0x2665, // heart
  0xAA: 0x2660, // spade
  0xAB: 0x2194, // arrowboth
  0xAC: 0x2190, // arrowleft
  0xAD: 0x2191, // arrowup
  0xAE: 0x2192, // arrowright
  0xAF: 0x2193, // arrowdown
  0xB0: 0x00B0, // degree
  0xB1: 0x00B1, // plusminus
  0xB2: 0x2033, // second
  0xB3: 0x2265, // greaterequal
  0xB4: 0x00D7, // multiply
  0xB5: 0x221D, // proportional
  0xB6: 0x2202, // partialdiff
  0xB7: 0x2022, // bullet
  0xB8: 0x00F7, // divide
  0xB9: 0x2260, // notequal
  0xBA: 0x2261, // equivalence
  0xBB: 0x2248, // approxequal
  0xBC: 0x2026, // ellipsis
  0xBD: 0xF8E6, // arrowvertex
  0xBE: 0xF8E7, // arrowhorizex
  0xBF: 0x21B5, // carriagereturn
  0xC0: 0x2135, // aleph
  0xC1: 0x2111, // Ifraktur
  0xC2: 0x211C, // Rfraktur
  0xC3: 0x2118, // weierstrass
  0xC4: 0x2297, // circlemultiply
  0xC5: 0x2295, // circleplus
  0xC6: 0x2205, // emptyset
  0xC7: 0x2229, // intersection
  0xC8: 0x222A, // union
  0xC9: 0x2283, // propersuperset
  0xCA: 0x2287, // reflexsuperset
  0xCB: 0x2284, // notsubset
  0xCC: 0x2282, // propersubset
  0xCD: 0x2286, // reflexsubset
  0xCE: 0x2208, // element
  0xCF: 0x2209, // notelement
  0xD0: 0x2220, // angle
  0xD1: 0x2207, // gradient
  0xD2: 0xF6DA, // registerserif
  0xD3: 0xF6D9, // copyrightserif
  0xD4: 0xF6DB, // trademarkserif
  0xD5: 0x220F, // product
  0xD6: 0x221A, // radical
  0xD7: 0x22C5, // dotmath
  0xD8: 0x00AC, // logicalnot
  0xD9: 0x2227, // logicaland
  0xDA: 0x2228, // logicalor
  0xDB: 0x21D4, // arrowdblboth
  0xDC: 0x21D0, // arrowdblleft
  0xDD: 0x21D1, // arrowdblup
  0xDE: 0x21D2, // arrowdblright
  0xDF: 0x21D3, // arrowdbldown
  0xE0: 0x25CA, // lozenge
  0xE1: 0x2329, // angleleft
  0xE2: 0x00AE, // registersans
  0xE3: 0x00A9, // copyrightsans
  0xE4: 0x2122, // trademarksans
  0xE5: 0x2211, // summation
  0xE6: 0x239B, // parenlefttp
  0xE7: 0x239C, // parenleftex
  0xE8: 0x239D, // parenleftbt
  0xE9: 0x23A1, // bracketlefttp
  0xEA: 0x23A2, // bracketleftex
  0xEB: 0x23A3, // bracketleftbt
  0xEC: 0x23A7, // bracelefttp
  0xED: 0x23A8, // braceleftmid
  0xEE: 0x23A9, // braceleftbt
  0xEF: 0x23AA, // braceex
  0xF1: 0x232A, // angleright
  0xF2: 0x222B, // integral
  0xF3: 0x2320, // integraltp
  0xF4: 0x23AE, // integralex
  0xF5: 0x2321, // integralbt
  0xF6: 0x239E, // parenrighttp
  0xF7: 0x239F, // parenrightex
  0xF8: 0x23A0, // parenrightbt
  0xF9: 0x23A4, // bracketrighttp
  0xFA: 0x23A5, // bracketrightex
  0xFB: 0x23A6, // bracketrightbt
  0xFC: 0x23AB, // bracerighttp
  0xFD: 0x23AC, // bracerightmid
  0xFE: 0x23AD, // bracerightbt
};
