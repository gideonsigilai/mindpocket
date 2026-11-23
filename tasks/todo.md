# Implementation Tasks

## Phase 1: Foundation
- [ ] Scaffold Windows Flutter project, dependencies, responsive theme, and navigation.
- [ ] Add the Rust resource probe through flutter_rust_bridge native assets.

### Checkpoint: Foundation
- [ ] Flutter dependencies resolve and Windows build exercises both native-asset hooks.

## Phase 2: Core Features
- [ ] Build paginated Hugging Face GGUF search and model-file selection.
- [ ] Build isolate-backed downloads with progress, cancellation, and optional SHA-256 verification.
- [ ] Build installed-model library and local streaming chat using llamadart.
- [ ] Add internet access toggle and OpenAI-compatible API address/token settings with secure storage.
- [ ] Add remote API connection testing and chat.

### Checkpoint: Core Features
- [ ] Focused parser/config tests pass and Windows smoke path works.

## Phase 3: Verification
- [ ] Run Windows-target build and app launch, then report exact verification evidence and limits.
