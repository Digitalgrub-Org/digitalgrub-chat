# Digitalgrub Chat

A chat app for teams, built on [Matrix](https://matrix.org): one Flutter
codebase for iOS, Android and the web, plus the small services we run beside
a [Synapse](https://github.com/element-hq/synapse) homeserver for push, calls
and meetings.

We built it at [Digitalgrub](https://digitalgrub.in) in Madurai, for our own
team and our clients, when the chat app our business ran on stopped being one
we could rely on. This repository is the code. It is not a hosted service and
it does not come with a server: you bring your own Matrix homeserver.

Some features of the hosted Digitalgrub Chat service are not part of this
repository.

## What is here

| Path | What it is |
| --- | --- |
| `apps/mobile` | The Flutter client: chats, groups, replies, reactions, edits, mentions, pins, search, voice messages, files, voice and video calls, meetings with guest links, push notifications. English and Tamil. |
| `deploy/compose.yaml` | A starting point for the chat side: Synapse, PostgreSQL, Caddy, nightly backups and a Sygnal push gateway. It does not include calls. |
| `deploy/synapse` | Renders `homeserver.yaml` from environment values, so no credential lives in a file you might commit. |
| `deploy/sygnal-ext` | Sygnal pushkins that tell a call from a message, so a locked phone rings like a phone. |
| `deploy/meet-guest` | Signs LiveKit tokens for meeting guests: a name and a meeting link, no account, one room. |
| `deploy/dg-admin` | Lets a server admin create accounts and reset passwords from the app, without exposing Synapse's admin API. |
| `deploy/livekit` | The LiveKit SFU configuration we run, for reference. |
| `docs/architecture.md` | How the app is put together, and why. |
| `docs/security-review.md` | The client-side security review. |

The Python services use the standard library only.

## What you need

- A **Matrix homeserver**. We run Synapse; the app talks the ordinary
  client-server API.
- For **calls and meetings**: a [LiveKit](https://livekit.io) SFU, the
  [lk-jwt-service](https://github.com/element-hq/lk-jwt-service) token
  service, and `deploy/meet-guest` if you want guest links.
- For **push**: a Sygnal gateway with your own FCM and APNs credentials, and
  your own Firebase project files for the app (`google-services.json`,
  `GoogleService-Info.plist`). Without them the app runs without push.
- **Flutter** stable and **Python 3**.

## Building the app

Nothing points at a real server by default. Tell the build where yours is:

```bash
cd apps/mobile
flutter pub get
flutter run \
  --dart-define=APP_HOMESERVER_URL=https://chat.example.com \
  --dart-define=APP_PUSH_GATEWAY_URL=https://chat.example.com/_matrix/push/v1/notify \
  --dart-define=APP_LIVEKIT_JWT_URL=https://chat.example.com/livekit/jwt \
  --dart-define=APP_MEET_GUEST_URL=https://chat.example.com/livekit/guest \
  --dart-define=APP_ADMIN_URL=https://chat.example.com/dg/admin
```

| Setting | Leave it empty to |
| --- | --- |
| `APP_HOMESERVER_URL` | (required: the default is a placeholder) |
| `APP_PUSH_GATEWAY_URL` | build without push |
| `APP_PUSH_APP_ID` | keep `com.digitalgrub.chat`; change it with your own app id |
| `APP_LIVEKIT_JWT_URL` | build without calls |
| `APP_MEET_GUEST_URL` | turn off guest links |
| `APP_ADMIN_URL` | hide the admin screen |
| `APP_WEB_PUSH_VAPID_KEY` | build the web app without push |

Release builds require HTTPS for every URL. If you publish your own build,
change the application id, the app name and the icon (see `NOTICE`).

## Tests

```bash
cd apps/mobile && flutter test
cd deploy/dg-admin && python3 -m unittest
cd deploy/synapse && python3 -m unittest
```

## Licence

GNU Affero General Public License v3.0, see `LICENSE`. The Digitalgrub name
and icon are not covered by it, see `NOTICE`.
