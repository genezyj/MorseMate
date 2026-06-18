"""MorseMate — LiveKit voice AI Morse-code tutor (backend agent).

Implements M1 of Document/technical_design.md: the real-time voice loop with a
Morse-instructor persona over the STT-LLM-TTS LiveKit Inference pipeline.

The `play_morse` tool (design §4.1) is wired but degrades gracefully when no
device client is connected — which is the normal case while verifying M1 in the
browser Playground. Deterministic on-device tone rendering lands in M3.
"""

from __future__ import annotations

import asyncio
import json
import os

from dotenv import find_dotenv, load_dotenv

from livekit import agents, rtc
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    RunContext,
    TurnHandlingOptions,
    function_tool,
    inference,
)

# Load secrets from the repo-root .env (design §8). find_dotenv() walks up from
# the cwd, so this works whether the agent is run from agent/ or the repo root.
load_dotenv(find_dotenv())


INSTRUCTIONS = """\
You are MorseMate, a warm, patient voice tutor that teaches Morse code by ear.

What you teach (Koch method):
- For this session, drill two characters: E (a single dit) and T (a single dah),
  at a slow, beginner-friendly 10 words per minute. Mix them up so the student
  can't predict which is next.

How you make sound — non-negotiable:
- To make the student HEAR Morse you MUST call the `play_morse` tool. Never voice
  dots and dashes yourself ("dit dah") — your voice can't hold a stable rhythm, and
  wrong timing teaches the wrong thing.
- If `play_morse` reports that no device is connected, tell the student playback needs
  the MorseMate app and keep practicing conversationally.

Each practice round — follow this loop exactly, in this order:
0. If user just come in to the session, make a self introduction and what will you teach.
    THEN give a short heads-up that the next one is coming — for example, "here's the first one, listen."
1. PLAY one test (here, one test means e, t, or any combination of e and t. Starting from 
    1-charactor sequence, then 2-character sequence) with
     `play_morse`, then stop and wait. Play only ONE per round.
2. Stop and wait. Let the student say what they think they heard.
3. When they answer, your spoken reply comes first and must finish before any sound:
   a. Judge their answer out loud. If they were RIGHT, say so warmly. If they were
      WRONG, gently correct them and tell them what it actually was.
   b. Then say a short heads-up that the next one is coming, e.g. "Okay, here's the
      next one, listen."
4. ONLY after speaking both (a) and (b), call `play_morse` for the next test. The
   `play_morse` call is always the LAST thing in your turn — never the first.
5. Then stop and wait, and repeat from step 2.

Critical ordering rules — the most important rules in this prompt:
- SPEAK FIRST, PLAY LAST. Never call `play_morse` at the start of a turn or before you
  have spoken. Your judgement and the "here's the next one" cue must be fully spoken
  before the tones play.
- One sound per turn: judge the previous answer, cue the next, then play exactly ONE
  test. Never play a new sound while still judging — finish speaking the judgement first.
- After you play, do not talk over the tones — wait for the student's answer.

Sending practice (the student can tap, too):
- Besides answering out loud, the student can tap Morse on an on-screen key and send
  it. You will receive their tapped letters as their answer — judge it exactly like a
  spoken answer (right → praise then cue the next; wrong → correct them, then continue).
- From time to time, invite the student to try *sending*: ask them to tap out one
  letter (E or T) on the key, then judge what they send back.

Style:
- Speak naturally and concisely. Everything you say is spoken aloud, so no on-screen
  formatting, emojis, asterisks, or symbols.
"""


class MorseTutor(Agent):
    def __init__(self, room: rtc.Room) -> None:
        self._room = room
        super().__init__(instructions=INSTRUCTIONS)

    @function_tool()
    async def play_morse(self, context: RunContext, text: str, wpm: int = 10) -> dict:
        """Play Morse code for `text` at `wpm` on the student's device.

        Call this whenever the student should hear Morse. Returns a status the
        you can narrate around.

        Args:
            text: The letters/digits to render as Morse (e.g. "E", "ET").
            wpm: Words per minute. Default 10 (a slow, beginner-friendly pace).
        """
        # Let whatever the tutor just said (the welcome, a cue, or feedback) finish
        # playing before the tones start. Otherwise the Morse can fire before the
        # speech reaches the student — e.g. tones before the welcome on cold start.
        try:
            await context.wait_for_playout()
        except Exception:
            pass
        # A short beat after the tutor's speech before the tones, so the audio
        # doesn't start abruptly on the heels of the spoken cue.
        await asyncio.sleep(1.0)

        remotes = list(self._room.remote_participants.values())
        if not remotes:
            return {"status": "no_device"}

        target = remotes[0].identity
        # Generous timeout: enough to cover playback of a short string + slack.
        timeout = max(10.0, len(text) * 1.5 + 2.0)
        try:
            ack = await self._room.local_participant.perform_rpc(
                destination_identity=target,
                method="play_morse",
                payload=json.dumps({"text": text.upper(), "wpm": wpm}),
                response_timeout=timeout,
            )
            return json.loads(ack)
        except Exception as exc:  # RPC failure must never crash the turn (design §4.3)
            return {"status": "error", "detail": str(exc)}


server = AgentServer()

# Dispatch mode. By default the agent uses *automatic* dispatch so it joins any
# room a frontend creates (e.g. the iOS app via a LiveKit sandbox token server).
# Set LIVEKIT_AGENT_NAME to switch to explicit/named dispatch (production, or the
# Agent Console which dispatches by name).
_agent_name = os.getenv("LIVEKIT_AGENT_NAME", "").strip()
_session_opts = {"agent_name": _agent_name} if _agent_name else {}


@server.rtc_session(**_session_opts)
async def entrypoint(ctx: agents.JobContext) -> None:
    session = AgentSession(
        stt=inference.STT(model="deepgram/nova-3", language="en"),
        llm=inference.LLM(model="openai/chat-latest"),
        tts=inference.TTS(
            model="cartesia/sonic-3",
            voice="9626c31c-bec5-4cca-baa8-f8ba9e84c8bc",
        ),
        turn_handling=TurnHandlingOptions(turn_detection=inference.TurnDetector()),
    )

    await session.start(room=ctx.room, agent=MorseTutor(room=ctx.room))

    # Tap-to-send: the device decodes the student's tapped Morse and sends it here
    # (design §4.2). Inject it as the student's answer and let the agent judge it.
    async def _on_submit_tap(data: rtc.RpcInvocationData) -> str:
        try:
            decoded = str(json.loads(data.payload).get("decoded", "")).strip()
        except Exception:
            decoded = ""
        session.generate_reply(
            instructions=(
                f"The student just tapped out '{decoded}' on the Morse key as their "
                "answer. Judge it against what you most recently asked or played: say "
                "whether it's right, correct them if not, then continue the practice loop."
            )
        )
        return "{}"

    ctx.room.local_participant.register_rpc_method("submit_tap", _on_submit_tap)

    # The client signals intent via the room name: "-cont-" means the student is
    # resuming, so skip the full introduction and go straight back to practice.
    is_continue = "-cont-" in (ctx.room.name or "")
    if is_continue:
        greeting = (
            "Welcome the student back in one short sentence and go straight into "
            "practice — do NOT repeat your full self-introduction. Then start the "
            "practice loop with the first test."
        )
    else:
        greeting = (
            "Greet the student warmly as MorseMate, say you'll teach Morse code by "
            "ear, and offer to start with the first two characters."
        )
    await session.generate_reply(instructions=greeting)


if __name__ == "__main__":
    agents.cli.run_app(server)
