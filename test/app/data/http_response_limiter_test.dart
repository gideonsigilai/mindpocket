import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/data/http_response_limiter.dart';

void main() {
  test('decodes UTF-8 split across response chunks', () async {
    final encoded = utf8.encode('Local café');
    final decoded = await readUtf8Limited(
      Stream<List<int>>.fromIterable([
        encoded.sublist(0, encoded.length - 1),
        encoded.sublist(encoded.length - 1),
      ]),
      maxBytes: 64,
      source: 'Test API',
    );

    expect(decoded, 'Local café');
  });

  test('rejects response bodies larger than the configured limit', () async {
    final body = utf8.encode('this response is too large');

    await expectLater(
      readUtf8Limited(
        Stream<List<int>>.value(body),
        maxBytes: 8,
        source: 'Test API',
      ),
      throwsFormatException,
    );
  });
}
