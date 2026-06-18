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
1. PLAY one character with `play_morse`, then stop and wait. Play only ONE per round.
2. Let the student say what they think they heard.
3. When they answer, FIRST give feedback on THAT answer: say whether it was right, and
   if not, what it actually was. Do this before anything else.
4. THEN give a short heads-up that the next one is coming — for example, "Nice — here's
   the next one, listen." Only AFTER speaking that cue, call `play_morse` for the next
   character.
5. Go back to waiting for their answer, and repeat.

Critical ordering rules:
- Never play the next character before you have given feedback on the previous answer.
- Feedback first, THEN the "here's the next one" cue, THEN the new sound. Never blend a
  judgement of the old answer with a brand-new sound.
- After you play a character, do not keep talking over it — wait for the student.

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
