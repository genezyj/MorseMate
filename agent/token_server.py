#!/usr/bin/env python3
"""Minimal dev token server for MorseMate.

Mints LiveKit join tokens from the root `.env` credentials so the iOS app never
holds the API secret (the secret stays on the backend). This replaces the now-
deprecated LiveKit Cloud sandbox token server.

Endpoint:
    GET|POST /token  ->  {serverUrl, roomName, participantToken, participantName}
    Optional query/JSON: roomName, identity, participantName

Run:
    cd agent && uv run python token_server.py

Dev-only: no auth, plain HTTP, permissive CORS. For production, front this with
your own authenticated HTTPS service and scope the grants (design §6.1, §8).
"""

from __future__ import annotations

import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from dotenv import find_dotenv, load_dotenv
from livekit import api

load_dotenv(find_dotenv())

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
API_KEY = os.environ["LIVEKIT_API_KEY"]
API_SECRET = os.environ["LIVEKIT_API_SECRET"]

HOST = os.getenv("TOKEN_SERVER_HOST", "0.0.0.0")
PORT = int(os.getenv("TOKEN_SERVER_PORT", "8080"))

DEFAULT_ROOM = "morse-demo"
DEFAULT_IDENTITY = "ios-student"


def mint_token(room: str, identity: str, name: str) -> str:
    grants = api.VideoGrants(room_join=True, room=room)
    return (
        api.AccessToken(API_KEY, API_SECRET)
        .with_identity(identity)
        .with_name(name)
        .with_grants(grants)
        .to_jwt()
    )


class Handler(BaseHTTPRequestHandler):
    def _params(self) -> dict[str, str]:
        params: dict[str, str] = {}
        query = parse_qs(urlparse(self.path).query)
        for key, values in query.items():
            if values:
                params[key] = values[0]
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
                if isinstance(body, dict):
                    params.update({k: str(v) for k, v in body.items()})
            except (ValueError, TypeError):
                pass
        return params

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # CORS preflight
        self._send(204, {})

    def do_GET(self) -> None:
        self._route()

    def do_POST(self) -> None:
        self._route()

    def _route(self) -> None:
        path = urlparse(self.path).path
        if path not in ("/token", "/"):
            self._send(404, {"error": "not found"})
            return
        params = self._params()
        identity = params.get("identity", DEFAULT_IDENTITY)
        name = params.get("participantName", identity)
        room = params.get("roomName", DEFAULT_ROOM)
        try:
            token = mint_token(room, identity, name)
        except Exception as exc:  # pragma: no cover - surfaces config issues
            self._send(500, {"error": str(exc)})
            return
        self._send(
            200,
            {
                "serverUrl": LIVEKIT_URL,
                "roomName": room,
                "participantToken": token,
                "participantName": name,
            },
        )

    def log_message(self, fmt: str, *args) -> None:  # quieter logs
        print("token-server:", fmt % args)


def _lan_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def main() -> None:
    ip = _lan_ip()
    print("MorseMate token server")
    print(f"  LiveKit:    {LIVEKIT_URL}")
    print(f"  Simulator:  http://localhost:{PORT}")
    print(f"  Device:     http://{ip}:{PORT}   <- set this in ios AppConfig.tokenServerURL")
    print(f"  Listening on {HOST}:{PORT} (Ctrl+C to stop)")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
