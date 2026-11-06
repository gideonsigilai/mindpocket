import 'dart:async';

import 'package:flutter/foundation.dart';

/// Debounces calls so a text field does not trigger a query per keystroke.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;
  bool _disposed = false;

  bool get isPending => _timer?.isActive ?? false;

  void run(VoidCallback action) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

/// Splits free text into lowercase word tokens, ignoring punctuation and short
/// noise. Used for tag suggestions and lexical relatedness, never presented as
/// calibrated confidence.
List<String> tokenize(String text) {
  final Set<String> stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'that',
    'this',
    'from',
    'into',
    'over',
    'your',
    'you',
    'are',
    'was',
    'were',
    'have',
    'has',
    'had',
    'but',
    'not',
    'use',
    'using',
    'about',
    'like',
    'just',
    'can',
    'will',
    'all',
    'any',
    'our',
    'out',
    'its',
    'it',
    'is',
    'of',
    'to',
    'in',
    'on',
    'at',
    'as',
    'by',
    'an',
    'a',
    'be',
    'or',
    'if',
    'so',
    'we',
    'my',
    'me',
    'do',
    'did',
  };
  return text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u00C0-\uFFFF]+'))
      .where((String token) => token.length > 2 && !stopWords.contains(token))
      .toList(growable: false);
}

/// Escapes a user query for an FTS5 MATCH expression: each token becomes a
/// quoted prefix term, so punctuation can never break the query.
String buildFtsQuery(String raw) {
  final List<String> tokens = raw
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u00C0-\uFFFF]+'))
      .where((String token) => token.isNotEmpty)
      .take(12)
      .toList(growable: false);
  if (tokens.isEmpty) return '';
  return tokens.map((String token) => '"$token"*').join(' ');
}

/// Compresses text to a single-line preview.
String preview(String? text, {int maxChars = 160}) {
  if (text == null) return '';
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxChars) return flat;
  return '${flat.substring(0, maxChars).trimRight()}…';
}
