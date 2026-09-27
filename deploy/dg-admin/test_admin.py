import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import admin

ADMIN_TOKEN = "tok-admin"
USER_TOKEN = "tok-user"
SERVER = "chat.example.com"


class FakeSynapse:
    """Answers the handful of Synapse calls the service makes.

    Records every write so a test can assert what reached the homeserver --
    in particular that a password never travels anywhere but the reset call.
    """

    def __init__(self):
        self.users = {f"@sara:{SERVER}": {"admin": False}, f"@ops:{SERVER}": {"admin": True}}
        self.writes = []
        self.down = False

    def __call__(self, path, token, method="GET", body=None):
        if self.down:
            raise ConnectionError("synapse down")
        who = {ADMIN_TOKEN: f"@admin:{SERVER}", USER_TOKEN: f"@sara:{SERVER}"}.get(token)
        if who is None:
            raise admin.SynapseRefused(401, "M_UNKNOWN_TOKEN")
        if path == "/_matrix/client/v3/account/whoami":
            return 200, {"user_id": who}
        caller_is_admin = who == f"@admin:{SERVER}"
        if path.endswith("/admin") and path.startswith("/_synapse/admin/v1/users/"):
            if not caller_is_admin:
                raise admin.SynapseRefused(403, "M_FORBIDDEN")
            uid = urllib.parse.unquote(path.split("/")[5])
            if uid == f"@admin:{SERVER}":
                return 200, {"admin": True}
            if uid not in self.users:
                raise admin.SynapseRefused(404, "M_NOT_FOUND")
            return 200, {"admin": self.users[uid]["admin"]}
        if not caller_is_admin:
            raise admin.SynapseRefused(403, "M_FORBIDDEN")
        if path.startswith("/_synapse/admin/v2/users/"):
            uid = urllib.parse.unquote(path.split("/")[5])
            if method == "GET":
                if uid in self.users:
                    return 200, {"name": uid}
                raise admin.SynapseRefused(404, "M_NOT_FOUND")
            if method == "PUT":
                self.writes.append(("create", uid, body))
                self.users[uid] = {"admin": body.get("admin", False)}
                return 201, {"name": uid}
        if path.startswith("/_synapse/admin/v1/reset_password/"):
            uid = urllib.parse.unquote(path.split("/")[5])
            if uid not in self.users:
                raise admin.SynapseRefused(404, "M_NOT_FOUND")
            self.writes.append(("reset", uid, body))
            return 200, {}
        raise AssertionError(f"unexpected call {method} {path}")


class AdminServiceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), admin.Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.synapse = FakeSynapse()
        admin._synapse = self.synapse
        admin._recent.clear()

    def call(self, method, path, body=None, token=ADMIN_TOKEN, ip="203.0.113.5"):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}", method=method
        )
        if token:
            request.add_header("Authorization", "Bearer " + token)
        request.add_header("X-Forwarded-For", ip)
        data = json.dumps(body).encode() if body is not None else None
        if data:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, data=data, timeout=5) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read() or b"{}")

    # --- who may call ---

    def test_no_token_is_refused_before_anything_else(self):
        status, body = self.call("POST", "/users", {"username": "new", "password": "longpass"}, token=None)
        self.assertEqual(status, 401)
        self.assertEqual(self.synapse.writes, [])

    def test_an_ordinary_user_is_refused(self):
        # Synapse's own admin flag is the authorization; the service holds no
        # list of its own to get out of date.
        status, body = self.call("POST", "/users", {"username": "new", "password": "longpass"}, token=USER_TOKEN)
        self.assertEqual(status, 403)
        self.assertEqual(self.synapse.writes, [])

    def test_a_dead_token_is_not_signed_in(self):
        status, _ = self.call("POST", "/users", {"username": "new", "password": "longpass"}, token="tok-stale")
        self.assertEqual(status, 401)

    # --- create ---

    def test_an_admin_creates_a_user(self):
        status, body = self.call(
            "POST", "/users", {"username": "Priya", "password": "longpass", "display_name": "Priya  R"}
        )
        self.assertEqual(status, 201)
        self.assertEqual(body["user_id"], f"@priya:{SERVER}")
        op, uid, sent = self.synapse.writes[0]
        self.assertEqual((op, uid), ("create", f"@priya:{SERVER}"))
        self.assertEqual(sent["displayname"], "Priya R")
        self.assertIs(sent["admin"], False, "this path must never mint an admin")

    def test_create_never_overwrites_an_existing_account(self):
        # The v2 PUT both creates and modifies. "Create" landing on a real
        # account would silently reset that person's password.
        status, body = self.call("POST", "/users", {"username": "sara", "password": "longpass"})
        self.assertEqual(status, 409)
        self.assertEqual(self.synapse.writes, [])

    def test_a_bad_username_is_refused(self):
        for bad in ("ab", "Has Space", "x" * 33, "@sara"):
            with self.subTest(username=bad):
                status, _ = self.call("POST", "/users", {"username": bad, "password": "longpass"})
                self.assertEqual(status, 400)
        self.assertEqual(self.synapse.writes, [])

    def test_a_short_password_is_refused_here_not_at_synapse(self):
        status, body = self.call("POST", "/users", {"username": "new", "password": "abc"})
        self.assertEqual(status, 400)
        self.assertIn("6", body["error"])
        self.assertEqual(self.synapse.writes, [])

    # --- reset ---

    def test_an_admin_resets_a_password_and_signs_out_sessions(self):
        status, body = self.call("POST", "/users/sara/password", {"password": "newlongpass"})
        self.assertEqual(status, 200)
        self.assertTrue(body["sessions_signed_out"])
        op, uid, sent = self.synapse.writes[0]
        self.assertEqual((op, uid), ("reset", f"@sara:{SERVER}"))
        self.assertEqual(sent, {"new_password": "newlongpass", "logout_devices": True})

    def test_an_admin_account_cannot_be_reset_from_here(self):
        # A compromised admin session locking out the other admin is the one
        # failure this must not enable.
        status, body = self.call("POST", "/users/ops/password", {"password": "newlongpass"})
        self.assertEqual(status, 403)
        self.assertEqual(self.synapse.writes, [])

    def test_resetting_nobody_is_a_404(self):
        status, _ = self.call("POST", "/users/ghost/password", {"password": "newlongpass"})
        self.assertEqual(status, 404)

    # --- the edges ---

    def test_synapse_down_is_a_502_not_a_crash(self):
        self.synapse.down = True
        status, _ = self.call("POST", "/users", {"username": "new", "password": "longpass"})
        self.assertEqual(status, 502)

    def test_rate_limited_per_real_address(self):
        for _ in range(admin._MAX_PER_WINDOW):
            self.call("POST", "/users/sara/password", {"password": "newlongpass"}, ip="198.51.100.9")
        status, _ = self.call("POST", "/users/sara/password", {"password": "newlongpass"}, ip="198.51.100.9")
        self.assertEqual(status, 429)
        # A spoofed first hop must not buy a fresh window: only the last hop
        # counts, and that is the one nginx wrote.
        status, _ = self.call(
            "POST", "/users/sara/password", {"password": "newlongpass"}, ip="1.2.3.4, 198.51.100.9"
        )
        self.assertEqual(status, 429)

    def test_health_needs_no_token(self):
        status, body = self.call("GET", "/healthz", token=None)
        self.assertEqual((status, body), (200, {"ok": True}))

    # --- am I an admin? ---

    def test_me_says_an_admin_is_one(self):
        status, body = self.call("GET", "/me")
        self.assertEqual((status, body), (200, {"user_id": f"@admin:{SERVER}", "admin": True}))

    def test_me_answers_an_ordinary_user_rather_than_refusing(self):
        status, body = self.call("GET", "/me", token=USER_TOKEN)
        self.assertEqual((status, body), (200, {"user_id": f"@sara:{SERVER}", "admin": False}))

    def test_me_needs_a_token(self):
        status, _ = self.call("GET", "/me", token=None)
        self.assertEqual(status, 401)

    def test_me_with_a_dead_token_is_not_signed_in(self):
        status, _ = self.call("GET", "/me", token="tok-expired")
        self.assertEqual(status, 401)

    def test_me_is_outside_the_rate_limit(self):
        for _ in range(admin._MAX_PER_WINDOW + 3):
            status, _ = self.call("GET", "/me")
        self.assertEqual(status, 200)
        self.assertEqual(self.synapse.writes, [])


if __name__ == "__main__":
    unittest.main()
