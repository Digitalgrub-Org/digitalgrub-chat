"""Two admin operations, reachable from the app: create a user, reset a password.

Synapse's admin API is deliberately not routed from the internet -- it also
lets a caller mint a login token for any account, which would turn a stolen
admin password into everyone's messages. This service exposes exactly two of
its operations and nothing else.

It holds no credentials of its own. The caller sends their Matrix access
token; Synapse says who that is, and Synapse's own admin flag on that account
is the authorization. So a token that is not a server admin's gets a 403 from
Synapse itself, and there is no service secret to leak.

POST /users                         {"username", "password", "display_name"?}
POST /users/<localpart>/password    {"password"}
GET  /me                         -> {"user_id", "admin"}
GET  /healthz

Standard library only, like the guest service: a bare python image with this
file mounted in.
"""

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SYNAPSE_URL = os.environ.get("SYNAPSE_URL", "http://synapse:8008").rstrip("/")
SERVER_NAME = os.environ.get("MATRIX_SERVER_NAME", "chat.example.com")

# Matches the app's sign-up rule and Synapse's own localpart grammar.
USERNAME = re.compile(r"^[a-z0-9._=-]{3,32}$")
# Mirrors password_config.policy.minimum_length in render_config.py.
MIN_PASSWORD = 6

_WINDOW_SECONDS = 60
_MAX_PER_WINDOW = 10
_recent = {}


class SynapseRefused(Exception):
    def __init__(self, status, errcode=None):
        super().__init__(f"{status} {errcode}")
        self.status = status
        self.errcode = errcode


def _synapse(path, token, method="GET", body=None):
    """One call to Synapse on the caller's behalf. Replaced wholesale in tests."""
    request = urllib.request.Request(SYNAPSE_URL + path, method=method)
    request.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, data=data, timeout=15) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        errcode = None
        try:
            errcode = json.loads(error.read()).get("errcode")
        except Exception:
            pass
        raise SynapseRefused(error.code, errcode)


def _user_id(localpart):
    return f"@{localpart}:{SERVER_NAME}"


def _quote(user_id):
    return urllib.parse.quote(user_id, safe="")


def _caller(token):
    """Who the token belongs to, and whether Synapse calls them an admin.

    The admin check is Synapse's own endpoint with the caller's own token: it
    answers 200 for an admin and 403 for anyone else, which is exactly the
    decision this service needs and one it should not be making itself.
    """
    _, who = _synapse("/_matrix/client/v3/account/whoami", token)
    user_id = who.get("user_id", "")
    if not user_id.endswith(":" + SERVER_NAME):
        return user_id, False
    try:
        _, flag = _synapse(f"/_synapse/admin/v1/users/{_quote(user_id)}/admin", token)
    except SynapseRefused as refused:
        if refused.status == 403:
            return user_id, False
        raise
    return user_id, bool(flag.get("admin"))


def _bearer(headers):
    """The access token from an Authorization header, or None."""
    auth = headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or len(auth) < 12:
        return None
    return auth[7:].strip()


def _is_admin(token, user_id):
    try:
        _, flag = _synapse(f"/_synapse/admin/v1/users/{_quote(user_id)}/admin", token)
    except SynapseRefused as refused:
        if refused.status == 404:
            return False
        raise
    return bool(flag.get("admin"))


def create_user(token, username, password, display_name):
    user_id = _user_id(username)
    # Existence first: the v2 PUT both creates and modifies, and "create"
    # must never quietly become "overwrite this person's password".
    try:
        _synapse(f"/_synapse/admin/v2/users/{_quote(user_id)}", token)
    except SynapseRefused as refused:
        if refused.status != 404:
            raise
    else:
        raise SynapseRefused(409, "M_USER_IN_USE")
    body = {"password": password, "admin": False, "deactivated": False}
    if display_name:
        body["displayname"] = display_name
    _synapse(f"/_synapse/admin/v2/users/{_quote(user_id)}", token, method="PUT", body=body)
    return user_id


def reset_password(token, username, password):
    user_id = _user_id(username)
    # An admin account cannot be reset from here. A compromised admin session
    # locking out the other admin is the one failure this must not enable;
    # that reset stays on the server, where it always was.
    if _is_admin(token, user_id):
        raise SynapseRefused(403, "IN.DIGITALGRUB.ADMIN_ACCOUNT")
    _synapse(
        f"/_synapse/admin/v1/reset_password/{_quote(user_id)}",
        token,
        method="POST",
        body={"new_password": password, "logout_devices": True},
    )
    return user_id


def _client_ip(handler):
    """The last X-Forwarded-For hop: the one nginx appended, not one the
    caller wrote. See the guest service for the incident behind this."""
    forwarded = handler.headers.get("X-Forwarded-For", "")
    hops = [hop.strip() for hop in forwarded.split(",") if hop.strip()]
    return hops[-1] if hops else handler.client_address[0]


def _rate_limited(ip):
    now = time.time()
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
        elif self.path == "/me":
            self._me()
        else:
            self._reply(404, {"error": "not found"})

    def _me(self):
        """Whether the caller may use the two operations above.

        So the app can decide whether to show its admin screen without holding
        an opinion of its own: the answer is Synapse's admin flag, the same one
        the POST endpoints act on. "Not an admin" is an ordinary 200 here, not
        a 403 -- the question is allowed, only the operations are not. Outside
        the rate limit, because every open of Settings asks it.
        """
        token = _bearer(self.headers)
        if token is None:
            self._reply(401, {"error": "sign in first"})
            return
        try:
            caller, admin = _caller(token)
        except SynapseRefused as refused:
            self._reply(401 if refused.status == 401 else 502, {"error": "not signed in"})
            return
        except Exception:
            self._reply(502, {"error": "server unavailable"})
            return
        self._reply(200, {"user_id": caller, "admin": admin})

    def do_POST(self):
        if _rate_limited(_client_ip(self)):
            self._reply(429, {"error": "slow down"})
            return
        token = _bearer(self.headers)
        if token is None:
            self._reply(401, {"error": "sign in first"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(length, 4096)) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._reply(400, {"error": "bad request"})
            return
        if not isinstance(body, dict):
            self._reply(400, {"error": "bad request"})
            return

        try:
            caller, admin = _caller(token)
        except SynapseRefused as refused:
            self._reply(401 if refused.status == 401 else 502, {"error": "not signed in"})
            return
        except Exception:
            self._reply(502, {"error": "server unavailable"})
            return
        if not admin:
            # Same answer for "not an admin" and "not our server": the
            # difference is not the caller's business.
            self._reply(403, {"error": "admin only"})
            return

        password = body.get("password")
        if not isinstance(password, str) or len(password) < MIN_PASSWORD:
            self._reply(400, {"error": f"password must be at least {MIN_PASSWORD} characters"})
            return

        try:
            if self.path == "/users":
                username = str(body.get("username", "")).strip().lower()
                if not USERNAME.match(username):
                    self._reply(400, {"error": "bad username"})
                    return
                display_name = re.sub(r"\s+", " ", str(body.get("display_name", ""))).strip()[:64]
                user_id = create_user(token, username, password, display_name)
                self._reply(201, {"user_id": user_id})
                return

            match = re.fullmatch(r"/users/([a-z0-9._=-]{3,32})/password", self.path)
            if match:
                user_id = reset_password(token, match.group(1), password)
                self._reply(200, {"user_id": user_id, "sessions_signed_out": True})
                return

            self._reply(404, {"error": "not found"})
        except SynapseRefused as refused:
            status = {
                404: 404,
                409: 409,
                403: 403,
            }.get(refused.status, 502)
            self._reply(status, {"error": refused.errcode or "refused"})
        except Exception:
            self._reply(502, {"error": "server unavailable"})

    def log_message(self, fmt, *args):
        # Paths carry usernames; bodies carry passwords and are never logged.
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
