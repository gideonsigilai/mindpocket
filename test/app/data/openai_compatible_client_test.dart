import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/data/openai_compatible_client.dart';

void main() {
  test('appends supported API routes to a versioned base URL', () {
    expect(
      apiResourceUri('https://api.example.test/openai/v1/', 'chat/completions'),
      Uri.parse('https://api.example.test/openai/v1/chat/completions'),
    );
    expect(
      apiResourceUri('http://127.0.0.1:11434/v1', 'models'),
      Uri.parse('http://127.0.0.1:11434/v1/models'),
    );
  });

  test('rejects unencrypted remote endpoints and credential-bearing URLs', () {
    expect(
      () => apiResourceUri('http://api.example.test/v1', 'models'),
      throwsFormatException,
    );
    expect(
      () => apiResourceUri('https://user:secret@api.example.test/v1', 'models'),
      throwsFormatException,
    );
    expect(
      () => apiResourceUri('https://api.example.test/v1?token=secret', 'models'),
      throwsFormatException,
    );
  });

  test('does not accept arbitrary resource paths', () {
    expect(
      () => apiResourceUri('https://api.example.test/v1', '../admin'),
      throwsArgumentError,
    );
  });
}
