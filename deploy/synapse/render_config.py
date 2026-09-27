import json
import os
import re
from pathlib import Path


DATA_DIR = Path(os.environ.get("SYNAPSE_DATA_DIR", "/data"))
CONFIG_PATH = DATA_DIR / "homeserver.yaml"
SERVER_NAME_PATH = DATA_DIR / ".server-name"
SYNAPSE_UID = 991
SYNAPSE_GID = 991


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def boolean(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise SystemExit(f"{name} must be true/false or yes/no")


def yaml_string(value: str) -> str:
    return json.dumps(value)


def validate_host(name: str, value: str) -> str:
    if "://" in value or "/" in value or any(char.isspace() for char in value):
        raise SystemExit(f"{name} must be a hostname, not a URL")
    return value.lower()


def validate_database_identifier(name: str, value: str) -> str:
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*", value):
        raise SystemExit(f"{name} contains unsupported characters")
    return value


def ensure_server_name(server_name: str) -> None:
    if SERVER_NAME_PATH.exists():
        existing = SERVER_NAME_PATH.read_text(encoding="utf-8").strip()
        if existing != server_name:
            raise SystemExit(
                "MATRIX_SERVER_NAME cannot change after initialization "
                f"({existing!r} != {server_name!r})",
            )
        return
    SERVER_NAME_PATH.write_text(f"{server_name}\n", encoding="utf-8")


def set_permissions(paths: list[Path]) -> None:
    get_effective_user_id = getattr(os, "geteuid", None)
    if get_effective_user_id is None or get_effective_user_id() != 0:
        return
    for path in paths:
        os.chown(path, SYNAPSE_UID, SYNAPSE_GID)


def main() -> None:
    server_name = validate_host(
        "MATRIX_SERVER_NAME",
        required("MATRIX_SERVER_NAME"),
    )
    public_host = validate_host(
        "MATRIX_PUBLIC_HOST",
        required("MATRIX_PUBLIC_HOST"),
    )
    database_name = validate_database_identifier(
        "POSTGRES_DB",
        required("POSTGRES_DB"),
    )
    database_user = validate_database_identifier(
        "POSTGRES_USER",
        required("POSTGRES_USER"),
    )
    database_password = required("POSTGRES_PASSWORD")
    # Defaults to the bundled `postgres` service. Deployments that reuse an
    # existing cluster point this at that container or host instead.
    database_host = os.environ.get("POSTGRES_HOST", "postgres").strip() or "postgres"
    database_port = os.environ.get("POSTGRES_PORT", "5432").strip() or "5432"
    if not database_port.isdigit():
        raise SystemExit("POSTGRES_PORT must be a number.")
    registration_enabled = boolean("SYNAPSE_ENABLE_REGISTRATION")
    registration_requires_token = boolean(
        "SYNAPSE_REGISTRATION_REQUIRES_TOKEN",
    )
    report_stats = boolean("SYNAPSE_REPORT_STATS")

    DATA_DIR.mkdir(mode=0o750, parents=True, exist_ok=True)
    media_dir = DATA_DIR / "media_store"
    media_dir.mkdir(mode=0o750, exist_ok=True)
    ensure_server_name(server_name)

    retention_block = ""
    modules_block = ""

    # Email is optional and off by default: a deployment that sets no SMTP
    # host renders exactly the config it always has. With a host set, Synapse
    # gains outbound mail -- which is what password reset and email
    # verification ride on -- and 3PID changes are enabled so people can
    # attach the address those emails go to.
    smtp_host = os.environ.get("SYNAPSE_SMTP_HOST", "").strip()
    email_enabled = bool(smtp_host)
    email_block = ""
    if email_enabled:
        smtp_port = os.environ.get("SYNAPSE_SMTP_PORT", "587").strip() or "587"
        if not smtp_port.isdigit():
            raise SystemExit("SYNAPSE_SMTP_PORT must be a number.")
        smtp_user = required("SYNAPSE_SMTP_USER")
        smtp_password = required("SYNAPSE_SMTP_PASS")
        # Must be an address the SMTP provider will accept as a sender. With
        # SES that means a verified identity, so there is no safe default to
        # invent here -- an unverified From fails at send time, which surfaces
        # as "reset emails never arrive" with nothing in our logs.
        notif_from = required("SYNAPSE_EMAIL_FROM")
        email_block = f"""
email:
  smtp_host: {yaml_string(smtp_host)}
  smtp_port: {smtp_port}
  smtp_user: {yaml_string(smtp_user)}
  smtp_pass: {yaml_string(smtp_password)}
  # STARTTLS on the submission port. force_tls would instead expect TLS from
  # the first byte (implicit TLS, port 465); SES supports both, but 587 with
  # STARTTLS is the path their docs lead with.
  require_transport_security: true
  notif_from: {yaml_string(notif_from)}
  app_name: Digitalgrub Chat
  # Notification digests are a different feature with its own noise budget;
  # this block exists for password reset and address verification only.
  enable_notifs: false
  client_base_url: {yaml_string(f'https://{public_host}/')}
  validation_token_lifetime: 1h
"""

    config = f"""# Generated by deploy/synapse/render_config.py. Do not edit in-place.
server_name: {yaml_string(server_name)}
public_baseurl: {yaml_string(f'https://{public_host}/')}
pid_file: null

listeners:
  - port: 8008
    type: http
    tls: false
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      # openid serves exactly one endpoint — /_matrix/federation/v1/openid/
      # userinfo — which the LiveKit token service uses to verify a caller's
      # OpenID token. It does not enable federation; the server still speaks
      # to no other homeserver.
      - names: [client, openid]
        compress: false
  - port: 9000
    type: metrics
    bind_addresses: ['0.0.0.0']

database:
  name: psycopg2
  txn_limit: 10000
  args:
    user: {yaml_string(database_user)}
    password: {yaml_string(database_password)}
    dbname: {yaml_string(database_name)}
    host: {yaml_string(database_host)}
    port: {database_port}
    cp_min: 5
    cp_max: 10

log_config: /config/log.config
media_store_path: /data/media_store
signing_key_path: /data/signing.key
registration_shared_secret_path: /data/registration_shared_secret

enable_registration: {str(registration_enabled).lower()}
enable_registration_without_verification: {str(registration_enabled).lower()}
registration_requires_token: {str(registration_requires_token).lower()}
enable_registration_captcha: false
disable_msisdn_registration: true
allow_guest_access: false
enable_3pid_lookup: false
# Adding an email address is only possible when the server can send the
# verification mail, so this follows the email switch.
enable_3pid_changes: {str(email_enabled).lower()}
{email_block}
password_config:
  enabled: true
  localdb_enabled: true
  policy:
    enabled: true
    # Deliberately permissive for an internal deployment: length only, no
    # character-class requirements, so a short numeric passcode is valid.
    # Online guessing is bounded by the rc_login limits below rather than by
    # password composition. Must match minimumPasswordLength in
    # apps/mobile/lib/features/authentication/domain/auth_repository.dart.
    minimum_length: 6
    require_digit: false
    require_lowercase: false
    require_uppercase: false
    require_symbol: false

require_auth_for_profile_requests: true
allow_public_rooms_without_auth: false
allow_public_rooms_over_federation: false
enable_room_list_search: false
room_list_publication_rules: []
user_directory:
  enabled: true
  search_all_users: true
  prefer_local_users: true
  exclude_remote_users: true

send_federation: false
federation_domain_whitelist: []
allow_profile_lookup_over_federation: false
trusted_key_servers: []
suppress_key_server_warning: true

url_preview_enabled: false
# 50M is Synapse's own default. The first deployment said 5M, which sounds
# sane until someone tries to share a phone photo: modern camera output is
# routinely 3-8MB, so half of a team's pictures would bounce with "too large".
# The client reads this limit from /_matrix/client/v1/media/config rather than
# hard-coding it, so changing it here is the whole change.
max_upload_size: 50M
max_avatar_size: 5M
allowed_avatar_mimetypes:
  - image/jpeg
  - image/png
  - image/webp
enable_authenticated_media: true
dynamic_thumbnails: false
thumbnail_sizes:
  - width: 32
    height: 32
    method: crop
  - width: 96
    height: 96
    method: crop
  - width: 256
    height: 256
    method: scale

enable_metrics: true
report_stats: {str(report_stats).lower()}
push:
  enabled: true
  include_content: false
  group_unread_count_by_room: true
  jitter_delay: 2s

rc_registration:
  per_second: 0.05
  burst_count: 3
rc_login:
  address:
    per_second: 0.02
    burst_count: 5
  account:
    per_second: 0.02
    burst_count: 5
  failed_attempts:
    per_second: 0.01
    burst_count: 3
rc_message:
  per_second: 0.5
  burst_count: 20
rc_user_directory:
  per_second: 0.1
  burst_count: 20
rc_reports:
  per_second: 0.1
  burst_count: 5

presence:
  enabled: true
  include_offline_users_on_sync: false
{retention_block}redaction_retention_period: 7d
user_ips_max_age: 28d
delete_stale_devices_after: 1y
encryption_enabled_by_default_for_room_type: off
auto_accept_invites:
  enabled: false
{modules_block}"""

    temporary_path = CONFIG_PATH.with_suffix(".yaml.tmp")
    temporary_path.write_text(config, encoding="utf-8")
    temporary_path.chmod(0o640)
    temporary_path.replace(CONFIG_PATH)
    SERVER_NAME_PATH.chmod(0o640)
    set_permissions([DATA_DIR, media_dir, CONFIG_PATH, SERVER_NAME_PATH])
    print(f"Rendered Synapse configuration for {server_name}")


if __name__ == "__main__":
    main()
