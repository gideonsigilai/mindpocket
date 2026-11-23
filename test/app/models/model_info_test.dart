import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/models/model_info.dart';

void main() {
  group('parseModelSearchResponse', () {
    test('keeps valid GGUF repositories and ignores malformed entries', () {
      final page = parseModelSearchResponse('''
        [
          {
            "id": "team/tiny-chat-GGUF",
            "downloads": 4200,
            "likes": 17,
            "gated": "auto",
            "tags": ["gguf", "text-generation", "conversational"]
          },
          {"id": "team/weights", "tags": ["safetensors"]},
          {"id": "../outside", "tags": ["gguf"]},
          {"tags": ["gguf"]}
        ]
      ''', nextCursor: 'page-2');

      expect(page.models, hasLength(1));
      expect(page.models.single.id, 'team/tiny-chat-GGUF');
      expect(page.models.single.downloads, 4200);
      expect(page.models.single.isGated, isTrue);
      expect(page.nextCursor, 'page-2');
    });
  });

  group('parseModelArtifacts', () {
    test('returns safe GGUF files ordered by size with the repository revision', () {
      final artifacts = parseModelArtifacts('''
        {
          "id": "team/tiny-chat-GGUF",
          "sha": "0123456789abcdef0123456789abcdef01234567",
          "gated": false,
          "siblings": [
            {
              "rfilename": "tiny-chat-Q8_0.gguf",
              "size": 2048,
              "lfs": {"sha256": "${'a' * 64}", "size": 2048}
            },
            {"rfilename": "README.md", "size": 512},
            {"rfilename": "../outside.gguf", "size": 1},
            {"rfilename": "tiny-chat-Q4_K_M.gguf", "size": 1024}
          ]
        }
      ''', repository: 'team/tiny-chat-GGUF');

      expect(artifacts.map((file) => file.filename), [
        'tiny-chat-Q4_K_M.gguf',
        'tiny-chat-Q8_0.gguf',
      ]);
      expect(artifacts.last.revision, '0123456789abcdef0123456789abcdef01234567');
      expect(artifacts.last.sha256, 'a' * 64);
    });

    test('rejects metadata for a different requested repository', () {
      expect(
        () => parseModelArtifacts(
          '{"id":"other/model","siblings":[]}',
          repository: 'team/model',
        ),
        throwsFormatException,
      );
    });
  });

  test('parses the next page cursor from a Link header', () {
    expect(
      parseNextCursor(
        '<https://huggingface.co/api/models?cursor=next%2Ftoken>; rel="next", '
        '<https://huggingface.co/api/models?cursor=previous>; rel="prev"',
      ),
      'next/token',
    );
  });
}
