import 'package:flutter/material.dart';

/// Soft, muted pastels used for the little avatar dots next to a person's
/// bubbles. Deriving the choice from the uid means everyone always sees the
/// same person in the same colour, across every chat and every device.
const List<Color> _personSeeds = <Color>[
  Color(0xFF9CCBAA), // soft mint
  Color(0xFFA9C6E4), // soft sky
  Color(0xFFBFC9ED), // periwinkle
  Color(0xFFE3A9B2), // blush pink
  Color(0xFFA8C4A2), // sage
  Color(0xFFEFC3A5), // apricot
];

/// Stable color for a person, picked from [_personSeeds] by hashing the uid.
Color colorForUid(String uid) {
  var hash = 0;
  for (final code in uid.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return _personSeeds[hash % _personSeeds.length];
}

/// A foreground that reads well on top of a bubble in [color].
Color onColorFor(Color color) {
  return color.computeLuminance() > 0.45
      ? const Color(0xFF33231C)
      : Colors.white;
}

/// The first letter of a display name, used inside avatar dots.
String initialFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}