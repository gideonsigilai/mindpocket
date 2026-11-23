import 'dart:convert';
import 'dart:typed_data';

Future<String> readUtf8Limited(
  Stream<List<int>> stream, {
  required int maxBytes,
  required String source,
}) async {
  final builder = BytesBuilder(copy: false);
  var receivedBytes = 0;
  await for (final chunk in stream) {
    if (chunk.length > maxBytes - receivedBytes) {
      throw FormatException(
        '$source response exceeded the ${maxBytes ~/ (1024 * 1024)} MB limit.',
      );
    }
    receivedBytes += chunk.length;
    builder.add(chunk);
  }
  return utf8.decode(builder.takeBytes());
}

Future<void> discardResponseBody(Stream<List<int>> stream) async {
  final subscription = stream.listen((_) {}, onError: (_) {});
  await subscription.cancel();
}
