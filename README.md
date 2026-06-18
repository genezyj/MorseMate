# MorseMate

A real-time **voice AI Morse-code tutor**. You talk to an AI instructor that teaches
Morse code by ear; when it wants you to *hear* Morse, it commands the device to play
deterministic tones. Built on [LiveKit](https://livekit.io) with a Python voice agent
and a native SwiftUI client.

- **`plan.md`** — product plan · **`Document/technical_design.md`** — technical design
- Subject chosen because Morse *is* sound, which justifies a voice-first, multisensory
  mobile experience (hear → feel → see).

## Architecture

```
SwiftUI app ──WebRTC audio──▶ LiveKit Room ──▶ Python Agent (AgentSession)
   │ ◀──────── RPC: play_morse(text, wpm) ───────┘  (LLM tool call)
   ▼                                    LiveKit Inference (STT · LLM · TTS)
On-device Morse engine (M3)
```

The split is the core design decision: the **LLM owns pedagogy/conversation**; the
**device owns exact Morse timing**. The agent never vocalizes Morse — it calls a
`play_morse` tool that the device renders deterministically. See
`Document/technical_design.md`.

**Status:** M1 (backend voice loop) ✅ · M2 (iOS voice round-trip) ✅ · M3 (on-device
Morse tones + haptics + visual) ✅

## Prerequisites

- **macOS** with **Xcode 16+** (iOS 17+), and a free Apple ID for device signing
- **[uv](https://docs.astral.sh/uv/)** — `brew install uv`
- A free **[LiveKit Cloud](https://cloud.livekit.io)** project (gives you STT/LLM/TTS
  via LiveKit Inference — no other AI keys needed)
- A physical **iPhone** + Mac on the **same Wi-Fi** (for the on-device experience)

## 1. Configure credentials

All secrets are read from a single `.env` in the repo root (never committed):

```bash
cp .env.example .env
```

Fill in `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` from your LiveKit Cloud
project (dashboard → Settings → Keys).

## 2. Start the backend (two terminals)

```bash
cd agent
uv sync                          # one-time: install dependencies

uv run python agent.py dev       # terminal A: the voice agent
uv run python token_server.py    # terminal B: mints iOS join tokens from .env
```

The token server prints the URLs to use, e.g.:

```
Simulator:  http://localhost:8080
Device:     http://192.168.1.50:8080   <- set this in ios AppConfig.tokenServerURL
```

Keep both running. (Details: `agent/README.md`.)

## 3. Run the app on your iPhone  *(primary experience)*

```bash
open ios/MorseMate.xcodeproj
```

1. **Token URL:** in `MorseMate/AppConfig.swift`, set `tokenServerURL` to the
   **Device** URL the token server printed (your Mac's LAN IP).
2. **Signing:** select the **MorseMate** target → **Signing & Capabilities** → choose
   your **Team**. If you get "failed to register bundle identifier," change the bundle
   id to something unique (e.g. `com.yourname.morsemate`).
3. Select your **iPhone** as the run destination and **Run** (⌘R).
4. With a free Apple ID, first run: on the phone trust the developer cert in
   **Settings → General → VPN & Device Management**.
5. In the app, tap **Start talking** and allow **Microphone** and **Local Network**
   when prompted. You should hear MorseMate greet you and can converse.

> Why Local Network: the phone fetches its session token from the token server on your
> Mac over Wi-Fi. The phone reaches LiveKit itself over the internet.

## Quick alternative: iOS Simulator (no signing, no device)

Set `AppConfig.tokenServerURL = "http://localhost:8080"` (the default), pick any iPhone
simulator, and run. The simulator uses your Mac's microphone, so you still get the full
voice loop — handy for a fast check. (Haptics, in M3, are device-only.)

## Troubleshooting

- **"Could not connect / token server" on device:** confirm the Mac and iPhone are on
  the **same Wi-Fi**, `tokenServerURL` is your Mac's **LAN IP** (not localhost), and the
  token server is running. If macOS prompts to allow incoming connections for Python,
  allow it. Avoid "guest"/client-isolated Wi-Fi.
- **Tapped "Allow" too fast / Local Network denied:** Settings → MorseMate → enable
  **Local Network** and **Microphone**.
- **Agent never joins (silence after connect):** make sure `agent.py dev` is running and
  `LIVEKIT_AGENT_NAME` is **unset** (the app relies on automatic dispatch).
- **First build is slow:** the LiveKit SDK downloads a WebRTC binary via SwiftPM once.

## Project layout

```
agent/     Python voice agent + token server (uv)
ios/       SwiftUI app (Xcode project; project.yml is the XcodeGen source)
Document/  plan.md, technical_design.md, workflow.md, reference notes
.env.example   required environment variables
```
## Notes

For reviewers: for your reference, it took around 3.5 hours for the implementation (plan, design, code gen, test on real device, and draft the workflow.md) starting from scratch, and I shipped P0 features within the given time frame. For personal interest, I love the product idea and plan to work on it as a side project! I might add some new features on top of the P0 features. I do respect and honor the evaluation process, so please feel free to evaluate my works based on this [commit](https://github.com/genezyj/MorseMate/commit/4f4ccbb56285ea0ba3e95174afe05c20ead0fdd5) and disregard the commits that came afterward (if any), especially if the time taken is an important evaluation criterion or concern.

## Future improvements

- **Adaptive progress & pacing** — track which characters are unlocked and the learner's
  running accuracy, and feed that to the agent so it paces the Koch progression. *(P1)*
- **Teach more characters and words** — extend beyond E/T to the full alphabet and digits,
  plus classic and useful sequences such as **SOS**. Probably gate it with difficulty level.
- **Polish the user experience and interaction logistics** — refine the visual/haptic
  design, state transitions, empty/error/recovery states, and the overall interaction
  flow. *(non-functional)*
- **Background running** — keep the audio session alive so a lesson continues when the app
  is backgrounded or the screen locks. *(P2)*
- **Post-session summary** — an LLM-generated recap of the characters covered, accuracy, and
  what to practice next, saved locally. *(P2)*
- **Session recovery** — reconnect cleanly and resume the lesson if the connection drops. *(P2)*
- **Production token path** — replace the dev token server with an authenticated HTTPS
  service and drop the local-network ATS exception. *(technical_design §6.1, §8)*


