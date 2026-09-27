# dg-admin — two admin operations, reachable from the app

Synapse's admin API is deliberately unreachable from the internet: among
other things it can mint a login token for any account, so exposing it would
turn a stolen admin password into everyone's messages. This service exposes
exactly two operations from it — create a user, reset a password — and holds
no credentials of its own. The caller's Matrix access token is the
authorization: Synapse says who it is and whether that account is a server
admin.

| Method | Path | Body | Result |
| --- | --- | --- | --- |
| `POST` | `/users` | `{"username", "password", "display_name"?}` | `201 {"user_id"}` — `409` if the name is taken |
| `POST` | `/users/<localpart>/password` | `{"password"}` | `200 {"user_id", "sessions_signed_out": true}` — `403` for an admin account |
| `GET` | `/me` | | `200 {"user_id", "admin"}` — whether the caller is a server admin |
| `GET` | `/healthz` | | `200` |

Every `POST` needs `Authorization: Bearer <matrix access token>` from a
server-admin account. Rate-limited to 10/min per address, keyed on the last
`X-Forwarded-For` hop (the one your proxy wrote). `GET /me` takes any signed-in
token, answers "not an admin" as an ordinary `200`, and is not rate-limited:
the app asks it every time Settings opens.

An admin account can never be reset from here — that stays a job done on the
server itself, so a compromised admin session cannot lock out the other
admin. This path can never create an admin either: `admin` is
pinned to `false` in the request it sends.

## Wiring

A compose service beside Synapse, reachable from your reverse proxy:

```yaml
  dg-admin:
    image: python:3.12-alpine
    command: ["python", "/app/admin.py"]
    environment:
      SYNAPSE_URL: http://synapse:8008
      MATRIX_SERVER_NAME: ${MATRIX_SERVER_NAME}
    volumes:
      - ./dg-admin:/app:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/healthz"]
      interval: 30s
```

Route a path of your choosing to it; the app finds it through
`APP_ADMIN_URL`. With nginx:

```nginx
    location /dg/admin/ {
        proxy_pass http://dg-admin:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Never route `/_synapse/admin/`: that is the API this service exists to keep
off the internet.

## Tests

```bash
cd deploy/dg-admin && python3 -m unittest test_admin
```

They run the real handler on a loopback port against a fake Synapse, and
record every write so a password can be shown never to travel anywhere but
the reset call.
