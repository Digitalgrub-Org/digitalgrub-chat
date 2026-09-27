# Digitalgrub Chat MVP Architecture

This document is the initial technical output required by `docs/mvp1.md`. It is
the implementation reference for MVP 1 and records decisions that should not be
left implicit in code.

## 1. Architecture summary

```text
Flutter Android/iOS app
  -> Matrix Client-Server API over HTTPS
  -> Caddy reverse proxy
  -> Synapse homeserver
       -> PostgreSQL (rooms, events, accounts, receipts, moderation data)
       -> persistent media volume (profile and group avatars only)
       -> optional Sygnal-compatible push gateway
```

The app is feature-first and depends on domain repository interfaces. Matrix
SDK types stay in the `matrix/` and feature data layers; presentation widgets do
not call `Client`, `Room`, or `Event` directly. Synapse is the messaging backend.
No custom chat protocol or duplicate message database is introduced.

The first server deployment is one Synapse process and one PostgreSQL instance.
Redis, workers, Kubernetes, and federation are deferred until measured load or
product requirements justify them.

## 2. Dependency list

Mobile runtime:

| Dependency | Purpose |
| --- | --- |
| Flutter / Material 3 | Android and iOS UI foundation |
| `flutter_riverpod` | State and dependency management |
| `go_router` | Declarative navigation and deep links |
| `matrix` 9.x | Matrix Client-Server API and sync model |
| `sqflite` + `path_provider` | Native `MatrixSdkDatabase` persistence |
| `flutter_secure_storage` | Access-token and sensitive session storage |
| `connectivity_plus` | Connectivity hint, never treated as reachability proof |
| `shared_preferences` | Non-sensitive preferences and onboarding state |
| `cached_network_image` | Avatar cache |
| `intl` + Flutter localization | English/Tamil messages and date formatting |
| `freezed` + `json_serializable` | Immutable domain/config models where useful |

Infrastructure images are pinned in Compose to Synapse 1.157.2, PostgreSQL
18.4, and Caddy 2.11.4. Image updates require release-note review, backup, and a
staging restore test.

## 3. Flutter folder structure

```text
apps/mobile/lib/
  app/
    app.dart
    localization/
    router/
    theme/
  core/
    config/
    errors/
    logging/
    network/
    storage/
    utilities/
    widgets/
  features/
    authentication/{data,domain,presentation}/
    chats/{data,domain,presentation}/
    contacts/{data,domain,presentation}/
    conversation/{data,domain,presentation}/
    groups/{data,domain,presentation}/
    moderation/{data,domain,presentation}/
    profile/{data,domain,presentation}/
    settings/{data,domain,presentation}/
  matrix/
    client/
    mappers/
    models/
    repositories/
    synchronization/
  notifications/
  main.dart
```

Repository interfaces live in feature domain layers. Matrix implementations
live under `matrix/repositories` or the relevant feature data layer. A small
FastAPI moderation service is not introduced unless Synapse's report APIs and
admin workflow prove insufficient during Stage 7.

## 4. Matrix event mapping

| Product behavior | Matrix representation |
| --- | --- |
| Plain text | `m.room.message` with `msgtype: m.text` |
| Reply | `m.relates_to.m.in_reply_to.event_id` plus reply fallback |
| Reaction | `m.reaction` with `m.relates_to.rel_type: m.annotation` |
| Edit | replacement `m.room.message` with `rel_type: m.replace` |
| Delete for everyone | redaction event targeting the original event |
| Delete for me | local hidden-event preference only |
| Typing | ephemeral `m.typing` |
| Read state | `m.read` receipt and fully-read marker |
| Direct chat | private room plus account-data `m.direct` mapping |
| Group metadata | `m.room.name`, `m.room.topic`, `m.room.avatar` |
| Membership | `m.room.member` |
| Roles | `m.room.power_levels` |
| Block user | account-data `m.ignored_user_list` |
| Report message | Matrix content-report API with local audit abstraction |
| Delivery | local send state and server acknowledgement; Matrix has no universal per-device delivered receipt |

The UI distinguishes local pending, failed, server-acknowledged, and read states.
It must not label a server acknowledgement as recipient-device delivery.

## 5. Offline synchronization design

`MatrixSdkDatabase` is the source for cached rooms, events, account data, and
sync position. `SecureMatrixDatabase` subclasses it to intercept client
credential reads/writes: access token, refresh token, and expiry are stored as
one record in `flutter_secure_storage`, while SQLite receives only a non-secret
marker. Tests inspect the raw SDK client record, reopen a file-backed cache, and
migrate legacy plaintext SDK credentials. No token is written to logs or
ordinary preferences.

One application-owned sync coordinator controls the single Matrix sync loop.
Startup order is:

1. Open secure storage and the Matrix database.
2. Construct the Matrix client and call `Client.init()`.
3. Render cached rooms immediately.
4. Resume from the stored sync token.
5. Reconcile local pending transactions with acknowledged event IDs.

Outgoing text uses a persisted transaction ID. The local timeline inserts a
pending item before network work begins. Retries reuse the same transaction ID,
which makes Matrix sends idempotent. Connectivity events may trigger a retry,
but only a successful request proves server reachability. Backoff is bounded,
exponential, and jittered. Lifecycle transitions pause unnecessary work without
starting a second sync loop.

The application-owned outbox is stored in `outgoing_messages.db` inside the app
support directory. Each row is scoped to the authenticated Matrix user and
contains the room, plain-text body, transaction ID, state, attempt count, and
next-attempt time. This has the same at-rest confidentiality boundary as the
unencrypted Matrix timeline cache: operating-system app sandboxing, not E2EE.
Outbox rows are deleted on logout. A crash during `sending` resets that row to
`pending` at startup; a crash after server acceptance is safe because replaying
the same Matrix transaction ID returns the same logical send rather than
creating a duplicate.

## 6. Screen list

Unauthenticated: splash, onboarding, login, registration, and forgot-password
placeholder.

Authenticated shell: Chats, Contacts, and Settings tabs.

Task routes: user search, conversation, new group, group details, user profile,
blocked users, own-profile editing, and message search. Dialogs/bottom sheets
cover chat creation, message actions, reactions, reports, destructive
confirmations, and conversation options.

## 7. Docker Compose architecture

- `caddy`: only service exposing host ports 80 and 443; terminates TLS, serves
  Matrix discovery, applies request limits, and proxies Matrix client paths.
- `synapse-init`: one-shot idempotent configuration and secret initialization.
- `synapse`: monolithic homeserver on the private application network.
- `postgres`: internal-only PostgreSQL database using `C` collation.
- `backup`: runs daily `pg_dump` archives and removes files beyond retention.
- `sygnal`: optional `push` profile; disabled for local development until FCM
  and APNs credentials are supplied.

Named volumes hold PostgreSQL data, Synapse configuration/media, Caddy state,
and backups. Recreating containers does not recreate these volumes. Metrics are
served only on the private monitoring network.

## 8. Environment variables

| Variable | Meaning |
| --- | --- |
| `MATRIX_SERVER_NAME` | Permanent Matrix ID domain; cannot be changed after launch |
| `MATRIX_PUBLIC_HOST` | Public HTTPS hostname handled by Caddy |
| `SYNAPSE_REPORT_STATS` | `yes` or `no` for upstream anonymous statistics |
| `SYNAPSE_ENABLE_REGISTRATION` | Controls public client registration |
| `POSTGRES_DB` | Synapse database name |
| `POSTGRES_USER` | Synapse database role |
| `POSTGRES_PASSWORD` | Strong deployment-only database password |
| `BACKUP_RETENTION_DAYS` | Local dump retention window |
| `BACKUP_INTERVAL_SECONDS` | Backup interval, default one day |
| `CADDY_ACME_EMAIL` | Certificate-expiry contact |
| `APP_HOMESERVER_URL` | Flutter build-time HTTPS Matrix base URL |
| `PUSH_GATEWAY_URL` | Optional Sygnal-compatible gateway URL |

FCM service-account and APNs signing credentials are external secret files, not
environment examples and never repository content.

## 9. Database and storage decisions

Synapse owns the server schema and migrations. PostgreSQL uses UTF-8 with `C`
locale as required by Synapse. No application service writes directly to
Synapse tables. Profile/group avatars use the persistent Synapse media volume;
general message media remains out of scope.

The client cache is not an independent message authority. It mirrors Matrix
state and stores only local concerns such as pending transactions, drafts,
pinned/archive choices, and hidden-for-me event IDs. Secure values use platform
key storage.

Daily dumps on the same server protect against operator/database errors,
not server loss. Before production acceptance, backups must also be copied to a
separate machine or storage location and a clean restore must be tested.

## 10. Stage-by-stage development plan

1. Architecture, Flutter shell, theme, localization, routing, and Compose stack.
2. Matrix client initialization, registration/login, secure session storage,
   logout, and restoration.
3. Cached chat list, user search, direct-room reuse/creation, timeline, and text
   sending.
4. Durable pending queue, incremental sync, reconnect/retry, deduplication, and
   history pagination.
5. Replies, reactions, edits, redactions/local deletion, typing, and receipts.
6. Private group creation, membership, details, and power-level administration.
7. Profiles/avatars, ignore/block, reporting, settings, and complete Tamil UI.
8. Push adapters, test matrix, profiling, security review, operations guides,
   and signed release checks.

Each stage ends with generation, formatting, analysis, tests, documentation
updates, and a focused commit after all checks pass.

Implementation status: Stages 1–7 are complete and Stage 8 is partly complete.
Stage 2 uses direct Matrix
password registration/login, supports Synapse dummy UI-auth, sets the required
display name, stores the optional unverified mobile number as private Matrix
account data, restores cached sessions before routing, refreshes expiring access
tokens through the SDK, and guarantees local logout when offline. Stage 3 adds
Matrix-isolated chat, user, and message repository interfaces; cached room and
timeline presentation; debounced directory search; `m.direct` room reuse or
creation; stable transaction IDs; and optimistic plain-text events. Stage 4
adds the SQLite outbox, restart recovery, per-room pending/failed state,
same-transaction manual and automatic retry, bounded exponential backoff with
jitter, connectivity-triggered flushing, and a lifecycle-aware owner for the
single incremental Matrix sync loop. Cached content remains visible throughout
connection failures and pagination. Stage 5 adds offline-safe reply and edit
relationships, Matrix reaction aggregation and toggling, replacement events,
redaction and persistent per-account local hiding, throttled typing updates,
typing presentation, read markers, and receipt-aware message status. Message
actions are exposed through a scrollable long-press sheet with destructive
confirmation. Stage 6 adds private group creation over `CreateRoomPreset.privateChat`
with encryption explicitly disabled, `m.room.topic` descriptions, invite-based
membership, and a group domain layer that exposes effective `m.room.power_levels`
as capability flags so administration controls are offered only when the account
actually holds the power to use them. Room-level `m.federate` is left at the
default so server configuration remains the single place federation is decided.
Stage 7 adds profile reads and edits, avatar upload, blocking, and reporting.
Display name goes through the profile field API; about text and the unverified
mobile number stay in `com.digitalgrub.profile` private account data and are
merged rather than replaced on each edit, so one field cannot erase another.
They are therefore visible only to their owner: publishing them to other users
would need extended profile support that Synapse does not guarantee. Avatars are
picked through an `AvatarPicker` abstraction so no feature layer imports
`image_picker`; the picker downscales to 512px and re-encodes before upload,
which is the required compression step, and the repository rejects anything
above 2 MB. Blocking uses the Matrix ignore list. The homeserver stops
delivering new events from an ignored user, but already-cached events survive,
so timelines also suppress blocked senders locally and refresh on account-data
syncs rather than only on room updates. Reporting is behind a `ReportRepository`
abstraction carrying reported user, room, event, category, comment, and
timestamp; the Matrix implementation serializes those into the report endpoints'
single reason string, and a dedicated FastAPI moderation service can replace it
without changing any caller. Stage 8 adds the push-ready architecture the
requirements call for: `PushRepository` registers an `http` pusher pointing at
the Matrix gateway with format `event_id_only`, so message content never reaches
the gateway, and `append: false` replaces rather than stacks pushers, which is
what prevents duplicate alerts. `PushTokenSource` is the single seam a messaging
plugin plugs into; its default implementation returns no token, which is the
documented push-disabled development mode and keeps the build free of FCM and
APNs credentials. Push activates only when `APP_PUSH_GATEWAY_URL` is supplied,
and both it and the homeserver URL must be HTTPS in release builds. Release
signing reads an uncommitted `android/key.properties`; a build without it still
succeeds for local use but is debug-signed and warns that it is not
distributable. The Material 3 light/dark themes use the Digitalgrub.in palette:
gold `#FFBE00`, deep teal `#0B2322`, slate `#364E52`, and neutral surfaces;
System, Light, and Dark selection persists locally.

## Licensing and encryption

Matrix Dart SDK and Synapse are AGPL-3.0-or-later. The application repository
must retain notices and meet corresponding-source obligations when distributed.
A final licensing review is required before store release.

MVP messages are protected in transit by HTTPS and readable by the homeserver.
E2EE is not enabled or claimed in MVP 1. A later security milestone may add the
SDK's audited Vodozemac integration, recovery keys, verification, and encrypted
backup only after cross-device tests pass.
