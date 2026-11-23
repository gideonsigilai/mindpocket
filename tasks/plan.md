# Implementation Plan: Windows-First Local AI Studio

## Overview

Create a responsive Flutter desktop app for searching Hugging Face GGUF models, downloading selected quantizations, running chat locally with an embedded llama.cpp runtime, and optionally chatting through an OpenAI-compatible API. Windows x64 is the verification target.

## Architecture Decisions

- Use `llamadart` for local GGUF inference. Its Windows build hook bundles a pinned llama.cpp runtime, avoiding a mandatory local C++/Clang toolchain and a custom inference wrapper.
- Use Hugging Face's model API for paginated GGUF discovery and repository file metadata. The supported local artifact scope is GGUF; raw safetensors and other formats are not directly runnable.
- Stream model downloads from Dart isolates, send progress to the UI, and verify the Hugging Face LFS SHA-256 when supplied.
- Use `flutter_rust_bridge` for a compact host resource probe (available RAM, CPU threads, and free model-storage disk space) to inform model-fit warnings. Keep model inference in the maintained llama.cpp Dart package rather than duplicating its C++ bridge in Rust.
- Use `ChangeNotifier` and Flutter Material primitives. The required GetX 5 release is not published on pub.dev (latest is 4.7.3), so avoid introducing obsolete GetX 4 patterns.
- Persist non-secret preferences locally; store API credentials with `flutter_secure_storage`. The network switch gates catalog, download, and remote API traffic while local inference remains available offline.
- Configure a user-editable OpenAI-compatible base URL and token, with a connection check and remote chat path.

## Task List

### Phase 1: Foundation
- [ ] Scaffold a Windows Flutter application and establish the responsive theme and navigation.
- [ ] Integrate the Rust resource probe through flutter_rust_bridge native assets.

### Checkpoint: Foundation
- [ ] Dependency resolution and Windows build prove both native-asset hooks work.

### Phase 2: Core Features
- [ ] Implement paginated Hugging Face GGUF search, file selection, and isolate-backed verified downloads.
- [ ] Implement installed-model library, local model loading, and streaming chat through llamadart.
- [ ] Implement network permission, OpenAI-compatible endpoint/token settings, secure token storage, and remote chat.

### Checkpoint: Core Features
- [ ] Run a focused Windows end-to-end smoke path and unit tests for external metadata parsing and URL/config boundaries.

### Phase 3: Polish
- [ ] Complete Windows verification and remove any temporary development artifacts.

### Checkpoint: Complete
- [ ] Search, download, load, chat, offline toggle, and remote API settings are reachable in the app.
- [ ] Windows build succeeds; any unavailable model-inference proof is reported explicitly.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| “All models” spans formats and gated repositories | Universal support is not a stable contract | Search all Hugging Face GGUF text-generation repositories; surface file metadata and optional Hugging Face token; reject unsupported formats clearly. |
| Large model downloads may be interrupted or exceed available resources | Lost time/disk space or failed model loads | Stream to disk in an isolate, report progress/cancel, verify known SHA-256, and show Rust-probed memory/disk information before download/load. |
| Rust and llama.cpp build integration on Windows | Build can fail on native hooks/toolchain incompatibility | Use FRB's native-assets backend and llamadart's prebuilt runtime; verify the actual Windows target once after integration. |
| Remote API credentials are sensitive | Credential exposure in app data/logs | Store tokens using the platform secure-storage plugin; never render or log their value. |

## Open Questions

- None blocking. The implementation is Windows-first and GGUF-focused; remote OpenAI-compatible APIs remain configurable.
