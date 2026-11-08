import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the TalkBack semantics contract: EyeCue must not teach the screen
/// reader its own interaction language.
///
/// On Android a node's semantic `hint` is announced *in addition to* the
/// platform's own hint, so an EyeCue-authored "Double tap to …" or "Hold for
/// three seconds …" string is spoken twice. Essential meaning belongs in
/// `label`/`value`; result wording (where needed at all) goes through
/// `hintOverrides`.
///
/// Visible copy such as `HOLD 3 SEC TO STOP` and the `Swipe left to start!`
/// headline is deliberately unaffected — only the exact semantic-string
/// prefixes below are rejected.
void main() {
  const forbidden = [
    "'Double tap",
    '"Double tap',
    "'Hold for three",
    '"Hold for three',
    // The concatenated semantic-meaning form, not the visible headline.
    "'Swipe left to start! Detection",
    '"Swipe left to start! Detection',
  ];

  Iterable<File> libSources() sync* {
    final dir = Directory('lib');
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }

  test('no semantic string teaches a screen-reader gesture', () {
    final hits = <String>[];
    for (final file in libSources()) {
      final text = file.readAsStringSync();
      for (final token in forbidden) {
        if (text.contains(token)) hits.add('${file.path}: $token');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
