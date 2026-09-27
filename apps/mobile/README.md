# Digitalgrub Chat mobile

Flutter Android/iOS client for the self-hosted Digitalgrub Matrix homeserver.

## Run

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter run --dart-define=APP_HOMESERVER_URL=https://chat.example.com
```

The homeserver URL must use HTTPS for release builds. Android emulators can use
an HTTP development server only in debug builds and only after adding an
explicit network-security exception; HTTPS is the normal development path.

## Verify

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

iOS builds require macOS and Xcode. The project includes the Keychain Sharing
entitlements required by `flutter_secure_storage` in Debug, Profile, and Release.

## Session storage

Room and event cache data uses the Matrix SDK's SQLite store. Access tokens,
refresh tokens, and expiration timestamps use Android Keystore-backed encrypted
storage or iOS Keychain and are deliberately absent from SQLite.

## Messaging checkpoint

Stage 3 reads the cached Matrix room list before waiting for a network sync,
keeps it updated from the SDK sync stream, searches the homeserver user
directory with a debounce, and calls `startDirectChat` with E2EE explicitly
disabled for the documented MVP security model. Existing `m.direct` rooms are
reused by the SDK. Conversation screens open the persisted SDK timeline and
send plain-text events with unique Matrix transaction IDs and optimistic
pending-event display.

Stage 4 adds an application-owned SQLite outbox. A message and its stable Matrix
transaction ID are committed locally before network work starts, merged into
the cached timeline immediately, retried with bounded exponential backoff, and
removed only after the homeserver acknowledges the idempotent send. Interrupted
`sending` records return to `pending` on restart, and failed messages provide a
manual retry action that keeps the same transaction ID. Per-account outbox data
is deleted on logout.

A single lifecycle-aware coordinator owns incremental SDK sync calls, resumes
from the SDK's persisted sync token, reacts to connectivity changes, and exposes
connecting, synchronizing, online, offline, expired-session, and unavailable
states without hiding cached content. Older timeline events load lazily while
preserving the reverse-list position. Stage 5 adds message relationships,
typing, and receipts.
