"""Mints LiveKit tokens for meeting guests.

A guest is someone with a meeting link and no account. They never touch
Matrix: this service checks that the link's room really is a meeting, then
signs a LiveKit JWT that admits them to that one room's media and nothing
else. Anyone with the link can join — that is the point of a meeting link,
and the codes are unguessable — but a link to a team chat gets a hard no,
because only rooms carrying the meeting marker are ever granted.

Runs inside the compose network next to Synapse. Standard library only, so
the container is a bare python image with this file mounted in.

POST /token   {"code": "abc-defg-hij" | "!roomid:server", "name": "Asha"}
          →   {"url": "<sfu websocket>", "jwt": "<livekit token>",
               "room_id": "!roomid:server"}
GET  /healthz
"""

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
# The SFU reachable from inside the compose network, for the room-create call.
LIVEKIT_API_URL = os.environ.get("LIVEKIT_API_URL", "http://livekit:7880")
LIVEKIT_KEY = os.environ["LIVEKIT_API_KEY"]
LIVEKIT_SECRET = os.environ["LIVEKIT_API_SECRET"]
SYNAPSE_URL = os.environ["SYNAPSE_URL"].rstrip("/")
SERVER_NAME = os.environ["MATRIX_SERVER_NAME"]
ADMIN_ACCOUNT_FILE = os.environ.get("ADMIN_ACCOUNT_FILE", "/secrets/admin-account")

MEETING_MARKER = "in.digitalgrub.meeting"
TOKEN_TTL_SECONDS = 6 * 3600

_admin_token = None


def _synapse(path, token=None, method="GET", body=None):
    request = urllib.request.Request(SYNAPSE_URL + path, method=method)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, data=data, timeout=10) as response:
        return json.loads(response.read())


def _admin_login():
    """Logs in with the same credentials file the invite-minting script uses."""
    creds = {}
    with open(ADMIN_ACCOUNT_FILE) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                key, _, value = line.partition("=")
                creds[key.strip()] = value.strip().strip('"')
    localpart = creds["user"].split(":", 1)[0].lstrip("@")
    result = _synapse(
        "/_matrix/client/v3/login",
        method="POST",
        body={
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": localpart},
            "password": creds["password"],
        },
    )
    return result["access_token"]


def _room_state(room_id):
    """Room state via the admin API, which sees rooms it is not a member of.

    Retries once through a fresh login so an expired token heals itself.
    """
    global _admin_token
    for attempt in (0, 1):
        if _admin_token is None:
            _admin_token = _admin_login()
        try:
            quoted = urllib.parse.quote(room_id, safe="")
            return _synapse(
                f"/_synapse/admin/v1/rooms/{quoted}/state", token=_admin_token
            )["state"]
        except urllib.error.HTTPError as error:
            if error.code in (401, 403) and attempt == 0:
                _admin_token = None
                continue
            raise
    raise RuntimeError("unreachable")


def _resolve(target):
    """Turns a meeting code or room id into a verified meeting room id."""
    if target.startswith("!"):
        room_id = target
    else:
        if not re.fullmatch(r"[a-z0-9-]{3,40}", target):
            return None
        alias = urllib.parse.quote(f"#{target}:{SERVER_NAME}", safe="")
        try:
            room_id = _synapse(f"/_matrix/client/v3/directory/room/{alias}")[
                "room_id"
            ]
        except urllib.error.HTTPError:
            return None
    try:
        state = _room_state(room_id)
    except urllib.error.HTTPError:
        return None
    # The marker is what separates "a meeting anyone with the link may enter"
    # from every other room on the server.
    if not any(event.get("type") == MEETING_MARKER for event in state):
        return None
    return room_id


def _b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


def _lk_room_alias(room_id):
    """The SFU-side name for a Matrix room's call, matching lk-jwt-service.

    Signed-in participants get their tokens from lk-jwt-service, which does
    not pass the Matrix room id to the SFU: it hashes ["<room id>",
    "m.call#ROOM"] (JSON, compact) with SHA-256 and uses the unpadded
    standard-base64 digest as the room name. A guest token must derive the
    identical name or the guest lands in a different, empty room while the
    team talks in the real one.
    """
    raw = json.dumps([room_id, "m.call#ROOM"], separators=(",", ":"))
    return base64.b64encode(hashlib.sha256(raw.encode()).digest()).rstrip(
        b"="
    ).decode()


def _admin_jwt(grant):
    now = int(time.time())
    header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = _b64(
        json.dumps(
            {
                "iss": LIVEKIT_KEY,
                "sub": "meet-guest-service",
                "iat": now,
                "nbf": now - 10,
                "exp": now + 60,
                "video": grant,
            },
            separators=(",", ":"),
        ).encode()
    )
    signature = _b64(
        hmac.new(
            LIVEKIT_SECRET.encode(), header + b"." + payload, hashlib.sha256
        ).digest()
    )
    return (header + b"." + payload + b"." + signature).decode()


def _ensure_lk_room(alias):
    """Creates the SFU room, because auto_create is off on purpose.

    Idempotent: LiveKit returns the existing room rather than erroring, with
    the same timeouts lk-jwt-service uses so a guest-created room behaves no
    differently from one a signed-in caller opened.
    """
    request = urllib.request.Request(
        LIVEKIT_API_URL + "/twirp/livekit.RoomService/CreateRoom",
        method="POST",
        data=json.dumps(
            {
                "name": alias,
                "empty_timeout": 300,
                "departure_timeout": 20,
                "max_participants": 0,
            }
        ).encode(),
    )
    request.add_header("Content-Type", "application/json")
    request.add_header(
        "Authorization", "Bearer " + _admin_jwt({"roomCreate": True})
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        response.read()


def _livekit_jwt(room_alias, name):
    now = int(time.time())
    header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = _b64(
        json.dumps(
            {
                "iss": LIVEKIT_KEY,
                "sub": f"guest:{secrets.token_hex(4)}",
                "iat": now,
                "nbf": now - 10,
                "exp": now + TOKEN_TTL_SECONDS,
                "name": name,
                "video": {
                    "room": room_alias,
                    "roomJoin": True,
                    "canPublish": True,
                    "canSubscribe": True,
                },
            },
            separators=(",", ":"),
        ).encode()
    )
    signature = _b64(
        hmac.new(LIVEKIT_SECRET.encode(), header + b"." + payload, hashlib.sha256).digest()
    )
    return (header + b"." + payload + b"." + signature).decode()


# Enough for a team's meetings; a scraper hammering the endpoint is not
# minting a token a second all day.
_recent = {}
_WINDOW_SECONDS = 60
_MAX_PER_WINDOW = 20


def _client_ip(handler):
    """The address the proxy saw, not the one the caller claims to have.

    nginx forwards `$proxy_add_x_forwarded_for`, which APPENDS the peer it
    actually observed to whatever the client sent. So the last hop is the
    trustworthy one and everything before it is caller-supplied. Reading the
    first element — the usual reading, and what this did — handed the rate
    limiter's key to the caller, who could then rotate it forever and mint
    tokens without limit.

    If a CDN or second proxy is ever put in front of nginx, this becomes that
    proxy's address for every caller and the limit turns global; the fix then
    is to count hops from the end, not to trust the front again.
    """
    forwarded = handler.headers.get("X-Forwarded-For", "")
    hops = [hop.strip() for hop in forwarded.split(",") if hop.strip()]
    return hops[-1] if hops else handler.client_address[0]


def _rate_limited(ip):
    now = time.time()
    # Drop everyone whose window has passed, not just this caller's entries:
    # the map is keyed by address, and pruning only the key in hand let it
    # grow for the life of the process.
    for stale in [
        key
        for key, times in _recent.items()
        if not times or now - times[-1] >= _WINDOW_SECONDS
    ]:
        del _recent[stale]
    window = [t for t in _recent.get(ip, []) if now - t < _WINDOW_SECONDS]
    if len(window) >= _MAX_PER_WINDOW:
        _recent[ip] = window
        return True
    window.append(now)
    _recent[ip] = window
    return False


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/healthz":
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/token":
            self._reply(404, {"error": "not found"})
            return
        if _rate_limited(_client_ip(self)):
            self._reply(429, {"error": "slow down"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(length, 4096)) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._reply(400, {"error": "bad request"})
            return
        code = body.get("code")
        name = re.sub(r"\s+", " ", str(body.get("name", ""))).strip()
        if not isinstance(code, str) or not name or len(name) > 40:
            self._reply(400, {"error": "code and name required"})
            return
        if any(ord(ch) < 32 for ch in name):
            self._reply(400, {"error": "bad name"})
            return
        try:
            room_id = _resolve(code)
        except Exception:
            self._reply(502, {"error": "server unavailable"})
            return
        if room_id is None:
            self._reply(404, {"error": "no such meeting"})
            return
        alias = _lk_room_alias(room_id)
        try:
            _ensure_lk_room(alias)
        except Exception:
            self._reply(502, {"error": "sfu unavailable"})
            return
        self._reply(
            200,
            {
                "url": LIVEKIT_URL,
                "jwt": _livekit_jwt(alias, name),
                "room_id": room_id,
            },
        )

    def log_message(self, fmt, *args):
        # One line per request, no client bodies: names do not belong in logs.
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
