import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("render_config.py")


def render(extra_env=None, expect_failure=False):
    """Runs the renderer in a scratch data dir and returns the config text.

    A subprocess rather than an import, because the script reads its
    environment at module load and a test must not depend on import order.
    """
    with tempfile.TemporaryDirectory() as data_dir:
        env = {
            "PATH": os.environ.get("PATH", ""),
            "SYNAPSE_DATA_DIR": data_dir,
            "MATRIX_SERVER_NAME": "dgchat.test",
            "MATRIX_PUBLIC_HOST": "dgchat.test",
            "POSTGRES_DB": "synapse",
            "POSTGRES_USER": "synapse",
            "POSTGRES_PASSWORD": "hunter2",
        }
        env.update(extra_env or {})
        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            env=env,
            capture_output=True,
            text=True,
        )
        if expect_failure:
            if result.returncode == 0:
                raise AssertionError("renderer unexpectedly succeeded")
            return result.stderr
        if result.returncode != 0:
            raise AssertionError(f"renderer failed: {result.stderr}")
        return (Path(data_dir) / "homeserver.yaml").read_text(encoding="utf-8")


SMTP_ENV = {
    "SYNAPSE_SMTP_HOST": "email-smtp.us-west-2.amazonaws.com",
    "SYNAPSE_SMTP_USER": "AKIAEXAMPLE",
    "SYNAPSE_SMTP_PASS": "sespassword",
    "SYNAPSE_EMAIL_FROM": "Digitalgrub Chat <moderation@example.com>",
}


class RenderConfigTest(unittest.TestCase):
    def test_no_smtp_means_no_email_anywhere(self):
        # The pre-email deployment, byte-for-byte in spirit: no email
        # section, and 3PID changes stay off because nothing could send the
        # verification mail.
        config = render()
        self.assertNotIn("\nemail:\n", config)
        self.assertNotIn("smtp", config)
        self.assertIn("enable_3pid_changes: false", config)

    def test_smtp_renders_the_email_section(self):
        config = render(SMTP_ENV)
        self.assertIn("\nemail:\n", config)
        self.assertIn('smtp_host: "email-smtp.us-west-2.amazonaws.com"', config)
        self.assertIn("smtp_port: 587", config)
        self.assertIn('notif_from: "Digitalgrub Chat <moderation@example.com>"', config)
        self.assertIn("require_transport_security: true", config)
        # Reset links must point at the public site, not a container name.
        self.assertIn('client_base_url: "https://dgchat.test/"', config)

    def test_smtp_turns_3pid_changes_on(self):
        # The reason the switch is coupled: an email section without 3PID
        # changes is a server that can mail nobody, because nobody can attach
        # the address the mail would go to.
        config = render(SMTP_ENV)
        self.assertIn("enable_3pid_changes: true", config)

    def test_notification_digests_stay_off(self):
        config = render(SMTP_ENV)
        self.assertIn("enable_notifs: false", config)

    def test_a_host_without_credentials_refuses_to_render(self):
        # Half an email config must fail at render time, where it names the
        # missing variable -- not at the first reset attempt weeks later.
        for missing in ("SYNAPSE_SMTP_USER", "SYNAPSE_SMTP_PASS", "SYNAPSE_EMAIL_FROM"):
            with self.subTest(missing=missing):
                env = {k: v for k, v in SMTP_ENV.items() if k != missing}
                stderr = render(env, expect_failure=True)
                self.assertIn(missing, stderr)

    def test_a_non_numeric_port_refuses_to_render(self):
        stderr = render({**SMTP_ENV, "SYNAPSE_SMTP_PORT": "tls"}, expect_failure=True)
        self.assertIn("SYNAPSE_SMTP_PORT", stderr)

    def test_the_password_lands_quoted(self):
        # An SES SMTP password is base64ish line noise; unquoted it is a YAML
        # accident waiting for a colon.
        config = render({**SMTP_ENV, "SYNAPSE_SMTP_PASS": "a:b#c"})
        self.assertIn('smtp_pass: "a:b#c"', config)



if __name__ == "__main__":
    unittest.main()
