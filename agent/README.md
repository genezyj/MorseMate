# MorseMate — Backend Agent

The LiveKit voice agent that powers MorseMate, a real-time voice AI Morse-code
tutor. It runs the STT-LLM-TTS pipeline (via **LiveKit Inference**, so no
per-provider API keys), holds a spoken conversation with a Morse-instructor
persona, and drives on-device Morse playback through the `play_morse` RPC tool.

## Requirements

- **Python ≥ 3.10**
- **[uv](https://docs.astral.sh/uv/)** — `brew install uv`
- A free **[LiveKit Cloud](https://cloud.livekit.io)** project (provides STT/LLM/TTS
  inference; no OpenAI/Deepgram/Cartesia accounts needed)

## Setup

### 1. Credentials → `.env`

All secrets are read from a `.env` file in the **repo root** (`../.env`), never
hardcoded. Create it from the template:

```bash
cp ../.env.example ../.env
```

Then fill in `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` from your
LiveKit Cloud project (dashboard → Settings → Keys).

**Or** let the LiveKit CLI populate them by linking a project:

```bash
brew install livekit-cli
lk cloud auth            # opens a browser, links a project
lk project list          # confirm your project is the default (*)
```

…then copy that project's URL/key/secret into `../.env`.

### 2. Install dependencies

```bash
uv sync
```

This creates `.venv/` and installs `livekit-agents` (1.6.x) and `python-dotenv`
from the pinned `uv.lock`.

## Run

The agent is a standard LiveKit Agents app with three run modes:

```bash
# Talk to it locally in your terminal (uses your Mac mic/speakers).
# Press Ctrl+B to toggle audio/text; Ctrl+C to quit.
uv run python agent.py console

# Connect to LiveKit Cloud as a worker; test from the browser playground.
uv run python agent.py dev

# Production mode.
uv run python agent.py start
```

### Verify the voice loop (M1)

1. `uv run python agent.py dev` — wait for `registered worker {agent_name: "morse-tutor", ...}`.
2. Open your project's Agents page: `https://cloud.livekit.io/projects/<project-id>/agents`.
3. Start a test session, allow the mic, and talk. MorseMate should greet you and
   offer to start teaching **E** and **T**.

Console mode (`agent.py console`) is the lowest-friction way to chat with it — no
browser or room setup required.

## Token server (for the iOS app)

The iOS app needs a join token but must never hold the API secret. `token_server.py`
is a minimal dev HTTP server that mints short-lived tokens from the root `.env`:

```bash
uv run python token_server.py
```

It prints the URLs to use (localhost for the Simulator, your Mac's LAN IP for a
physical device) — put one in the app's `AppConfig.tokenServerURL`. It exposes
`GET|POST /token` returning `{serverUrl, roomName, participantToken, participantName}`.

Dev-only: no auth, plain HTTP, permissive CORS. Production replaces it with an
authenticated HTTPS service (this also lets you drop the app's ATS exception).
This replaces the now-deprecated LiveKit Cloud sandbox token server.

## What it does

- **Persona & method:** a patient Morse instructor using the **Koch method** —
  starts with E (dit) and T (dah) at 20 WPM, drills, then adds characters.
- **`play_morse(text, wpm)` tool:** when the student should *hear* Morse, the LLM
  calls this tool, which sends an RPC to the connected device to render
  deterministic tones (design §4.1). It **never** vocalizes Morse itself.
  - During M1 (no app connected), `play_morse` returns `{"status": "no_device"}`
    and the agent keeps teaching conversationally. On-device tone rendering is M3.

## Notes

- **Named agent / dispatch.** The agent registers with `agent_name="morse-tutor"`
  (explicit dispatch), so it joins only when dispatched by that name — which the
  Cloud Agent Console does for you. If you connect a frontend that expects
  *automatic* dispatch and the agent doesn't join, that's why; remove the
  `agent_name` argument in `agent.py` to switch to automatic dispatch for local
  development.
- **Model files.** `uv run -m livekit.agents download-files` fetches any plugin
  model assets. The current pipeline uses server-side turn detection (LiveKit
  Inference) and needs no local models.
