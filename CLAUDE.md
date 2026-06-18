# CLAUDE.md

## Goal
Build a native iOS Morse code tutor using LiveKit.
Prioritize one reliable P0 loop: voice prompt → structured Morse command → local playback/UI → spoken answer → feedback.
This is a small take-home project; prefer a complete vertical slice over extra features.

## Core Constraints
- Do not add authentication, cloud sync, curriculum systems, RAG, or unrelated infrastructure unless requested.
- Separate SwiftUI, session orchestration, LiveKit, Morse logic, audio, haptics, and configuration.
- Keep Morse mappings, validation, and timing deterministic and testable.
- The LLM may choose lesson content and wording, but must not generate Morse mappings or low-level timing.
- Use structured RPC or data messages between backend and iOS.
- Generate Morse audio locally; do not transmit generated audio.
- Keep secrets out of the iOS app and repository.
- Generate LiveKit tokens on the backend only.
- Read configuration from root `.env`; keep `.env.example` complete and `.env` ignored.
- Avoid unnecessary dependencies, abstractions, agents, skills, and broad refactors.

## Workflow
Work one milestone at a time:
1. Configuration and project structure
2. Minimal LiveKit voice session
3. Structured backend-to-client communication
4. Deterministic Morse playback
5. Agent tool integration
6. Mobile polish, recovery, and documentation

Inspect existing code and relevant files in `references/` before editing.
Limit changes to the active milestone; do not silently begin the next one.
Use Plan Mode for cross-cutting changes, schema changes, security work, or major refactors.

## iOS Requirements
- Keep UI updates on the main actor and orchestration out of SwiftUI views.
- Model connection, listening, speaking, playback, error, and disconnected states explicitly.
- Clean up resources on cancellation, disconnect, and playback failure.
- Synchronize visual and haptic progress with audio playback.
- Restore microphone and audio-session state after playback in every path.
- Require physical-device testing for microphone, speaker, haptics, and timing.

## Verification
Run relevant backend tests, Swift tests, Xcode builds, and `git diff --check`.
Do not claim success for commands or device behavior that were not verified.
If credentials, signing, hardware, or external services block verification, state exactly what remains manual.

## Documentation and Done
Keep `README.md`, `plan.md`, and `.env.example` consistent with the implementation.
Do not document optional or untested behavior as complete.
Done means the backend starts, the iOS app builds, the full tutoring loop works, secrets are absent, Morse logic is tested, errors are visible, and real-device audio/haptic behavior has been checked.
