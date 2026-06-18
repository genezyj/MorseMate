"""MorseMate — LiveKit voice AI Morse-code tutor (backend agent).

Implements M1 of Document/technical_design.md: the real-time voice loop with a
Morse-instructor persona over the STT-LLM-TTS LiveKit Inference pipeline.

The `play_morse` tool (design §4.1) is wired but degrades gracefully when no
device client is connected — which is the normal case while verifying M1 in the
browser Playground. Deterministic on-device tone rendering lands in M3.
"""

from __future__ import annotations

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

Teaching method — the Koch method:
- Start the student on just two characters: E (a single dit) and T (a single dah),
  at a comfortable 20 words per minute.
- Drill those two until the student is accurate, then introduce one new character
  at a time. For this session, focus on E and T.
- Keep turns short and conversational. Ask the student to identify what they hear,
  give quick encouraging feedback, and keep them practicing.

Hard rule about sound:
- To make the student HEAR Morse, you MUST call the `play_morse` tool. Never speak
  dots and dashes aloud yourself ("dit dit dah") — your voice cannot hold a stable
  rhythm, and wrong timing teaches the wrong thing.
- After calling `play_morse`, talk about what you just played and ask the student
  what they heard.
- If `play_morse` reports that no device is connected, tell the student that audio
  playback needs the MorseMate app and keep teaching conversationally for now.

Style:
- Speak naturally and concisely. No on-screen formatting, emojis, asterisks, or
  symbols — everything you say is spoken aloud.
"""


class MorseTutor(Agent):
    def __init__(self, room: rtc.Room) -> None:
        self._room = room
        super().__init__(instructions=INSTRUCTIONS)

    @function_tool()
    async def play_morse(self, context: RunContext, text: str, wpm: int = 20) -> dict:
        """Play Morse code for `text` at `wpm` on the student's device.

        Call this whenever the student should hear Morse. Returns a status the
        you can narrate around.

        Args:
            text: The letters/digits to render as Morse (e.g. "E", "ET").
            wpm: Words per minute. Default 20.
        """
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

    await session.generate_reply(
        instructions=(
            "Greet the student warmly as MorseMate, say you'll teach Morse code by "
            "ear, and offer to start with the first two characters."
        )
    )


if __name__ == "__main__":
    agents.cli.run_app(server)
