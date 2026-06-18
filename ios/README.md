# MorseMate — iOS App

The SwiftUI client for MorseMate. It connects to a LiveKit room, streams your
microphone to the voice agent, and plays the tutor's speech — the M2 voice
round-trip. On-device Morse tone playback (`play_morse`) lands in M3.

See `../Document/technical_design.md` §6 for the design.

## Requirements

- **Xcode 16+**, iOS 17+ deployment target
- **[XcodeGen](https://github.com/yonsm/XcodeGen)** — `brew install xcodegen`
  (the `.xcodeproj` is generated from `project.yml`)
- The backend **agent** and **token server** running (see `../agent/README.md`)

## Setup

### 1. Generate the Xcode project

```bash
cd ios
xcodegen generate
open MorseMate.xcodeproj
```

`project.yml` is the source of truth; re-run `xcodegen generate` after changing
it. The LiveKit Swift SDK (`client-sdk-swift`) is pulled in via Swift Package
Manager on first build (it downloads a WebRTC binary, so the first build is slow).

### 2. Point the app at the token server

The app holds **no API secret**. It fetches a short-lived join token from the
MorseMate dev **token server** (`../agent/token_server.py`), which mints tokens
from the backend `.env` credentials.

Start the token server (`cd ../agent && uv run python token_server.py`) — it
prints the URLs to use — then set `MorseMate/AppConfig.swift`:

```swift
// Simulator:
static let tokenServerURL = "http://localhost:8080"
// Physical device (use your Mac's LAN IP, which the token server prints):
static let tokenServerURL = "http://192.168.x.x:8080"
```

> The app talks to the token server over plain HTTP on the local network, so the
> dev build sets an App Transport Security exception (`NSAllowsArbitraryLoads`)
> in `project.yml`. Production uses an HTTPS token server and drops the exception.

## Build & run

- **Simulator** (compile/UI + connection check): build and run the `MorseMate`
  scheme. The simulator can reach the token server and hear the agent, but has no
  real microphone, so use it to verify the flow — not the full voice loop.
- **Device** (the real test): select your iPhone, set a Development Team for
  signing (target → Signing & Capabilities), and run. Tap **Start talking**,
  allow microphone access, and you should hear MorseMate greet you.

For the agent to join your room, run it with **automatic dispatch** (the default —
`uv run python agent.py dev`; do not set `LIVEKIT_AGENT_NAME`).

## What works at M2

- Connect / disconnect with a LiveKit room (token from the backend token server).
- Microphone permission flow.
- Live two-way voice conversation with the tutor.
- Agent-state surface (`waiting / listening / thinking / speaking`) and a speaking
  indicator, read from the agent participant's `lk.agent.state` attribute.

The custom audio session + on-device Morse engine (deterministic tones, haptics,
visual flash) — and the client-side `play_morse` RPC handler — are M3.
