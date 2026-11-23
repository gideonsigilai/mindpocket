# Loom Local AI

A cross-platform Flutter studio for downloading and chatting with local AI models. Loom
can also serve its currently selected model to other apps through a local
OpenAI-compatible API.

## Android and iOS

The app includes on-device GGUF inference for Android and iOS. Run it with
`flutter run -d <device-id>` after installing dependencies. iOS builds require
macOS/Xcode and iOS 16.4 or later. Model size, inference speed, background
execution, and thermal behavior depend on the device and mobile OS, so they are
not identical to Windows.

### Build an unsigned iOS IPA

The **Build unsigned iOS IPA** GitHub Actions workflow runs on pushes, pull
requests, and manual dispatch. Download the `local-ai-studio-unsigned-ipa`
artifact from the completed run. It contains `local_ai_studio-unsigned.ipa`;
code signing is intentionally omitted, so sign it before installing or
distributing it.

To load a GGUF model already on your computer, open **My models** and choose
**Load from storage**. Loom copies the selected file into its local library
before loading it.
Only complete standalone chat models can be loaded; Qwen3.5 speculative draft
files must be used with their matching base model.

## Use Loom from another app

1. In **Settings → Use Loom from another app**, create an API key. The secret is
   shown only once; copy it or the generated provider config before hiding it.
   Loom stores the key hash in secure storage, and you can revoke keys at any
   time. Create a different key for each app or environment.
2. Start the API. By default it listens only on `127.0.0.1:8765`. Select a model
   in Chat and load a local model (or select a configured remote model) before
   sending chat requests.
3. Configure your OpenAI-compatible client with the generated YAML, or use:

   ```yaml
   providers:
     loom-local:
       api: openai-completions
       apiKey: YOUR_GENERATED_KEY
       baseUrl: http://127.0.0.1:8765/v1
       models:
         - id: YOUR_MODEL_ID
           name: YOUR_MODEL_ID
   ```

### Endpoints

- `GET /v1/models` — lists the currently available model.
- `POST /v1/chat/completions` — accepts OpenAI-style `model` and `messages`
  fields and returns a non-streaming chat completion.

Send `Authorization: Bearer YOUR_GENERATED_KEY` with both requests. Chat bodies
are limited to 1 MB, 64 messages, and 128 KB per message. Set
`stream: true` for OpenAI-compatible server-sent events, or omit it for a normal
JSON response.

The service is intentionally loopback-only: it is available to apps running on
the same computer, not to other devices or the public internet. Do not put the
API key in browser/client-side code or expose this HTTP endpoint through port
forwarding. A remotely accessible deployment needs a separate authenticated
HTTPS gateway.
