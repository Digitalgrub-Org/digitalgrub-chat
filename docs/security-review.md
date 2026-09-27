# Digitalgrub Chat security review

Reviewed: 2 August 2026

Scope: the Flutter client in `apps/mobile` and the repository's secret hygiene.
The Synapse, PostgreSQL, and Caddy deployment is covered separately in
[`operations.md`](operations.md); a server-side penetration test is not part of
this review.

Toolchain at review time: Flutter 3.44.4, Dart 3.12.2, Matrix Dart SDK 9.0.0.

## Summary

Four issues were found and fixed during this review. Three were preventable
footguns rather than live exploits; one would have shipped a debug-signed
release build. Nine controls were checked and confirmed working. Seven residual
risks are accepted and documented, the most significant being the deliberate
absence of end-to-end encryption in MVP 1.

## Findings fixed in this review

### 1. Credential fragments could reach the device log — medium

`SecureMatrixDatabase._readCredentials` interpolated the caught exception into
`debugPrint` when stored credentials failed to parse. `jsonDecode` throws a
`FormatException` whose `toString()` embeds the offending source, and that
source is the credentials blob holding the Matrix access and refresh tokens. A
partially corrupted record could therefore print token material to logcat, which
is readable over adb and by anything with log access on older Android versions.

Fixed by logging a fixed reason string and never the exception. The blob is
still deleted on parse failure, which was already correct.

### 2. Release builds were signed with debug keys — high for release readiness

`android/app/build.gradle.kts` carried the Flutter template's placeholder that
signs release builds with the debug keystore. Any artifact produced by
`flutter build apk --release` would have been debug-signed, and Play would
reject it — or worse, a debug-signed build could be distributed sideloaded and
would share a signing identity with every other developer's debug builds.

Fixed with a real signing configuration sourced from `android/key.properties`,
which is git-ignored. When that file is absent the build still succeeds using
debug keys so `flutter run --release` keeps working, but Gradle emits a loud
warning that the artifact is not distributable. Code shrinking and resource
shrinking are now enabled with a ProGuard rule set.

### 3. Release and push credentials were not git-ignored — medium

The root `.gitignore` covered `.env`, `*.p12`, `*.jks`, and `key.properties`,
but not the credential types Stage 8 introduces: APNs `.p8` keys, `*.keystore`,
`google-services.json`, `GoogleService-Info.plist`, provisioning profiles, and
certificates. Nothing sensitive had been committed, so this was a latent risk
rather than an incident.

Fixed by extending `.gitignore` before those files exist on any machine.

### 4. Delete-for-me records survived logout — low

`HiddenEventStore` persists the event IDs a user has hidden locally. The outbox
next to it is cleared on logout; this store was not, and had no API to clear it.
Records are keyed by user ID, so this was residue on a signed-out device rather
than cross-account leakage, and it stores identifiers rather than message
content.

Fixed by adding `deleteForUser` and calling it in the logout path alongside the
outbox, with a regression test.

## Controls verified

| Control | Status |
| --- | --- |
| Matrix access and refresh tokens stored via `flutter_secure_storage` | Confirmed |
| SQLite client record holds a non-secret marker, never plaintext tokens | Confirmed |
| Android `allowBackup=false`, so encrypted session data cannot be restored elsewhere | Confirmed |
| iOS Keychain uses this-device-only accessibility | Confirmed |
| No App Transport Security exemptions in `Info.plist` | Confirmed |
| `APP_HOMESERVER_URL` and `APP_PUSH_GATEWAY_URL` rejected unless HTTPS in release | Confirmed |
| No secret, keystore, dump, or `.env` tracked in git | Confirmed |
| Push registration uses `event_id_only`, keeping message content off the gateway | Confirmed |
| Logout clears the outbox and, after this review, hidden-event records | Confirmed |

The access token is attached as a bearer header when loading avatars and other
authenticated media. Those requests go only to the configured homeserver over
HTTPS and the header is not persisted by the image cache, which keys on URL.

## Accepted residual risks

1. **No end-to-end encryption.** Messages are protected by HTTPS in transit and
   are readable by the homeserver. This is an explicit MVP 1 decision. The
   product must not be described as end-to-end encrypted until the SDK's
   Vodozemac integration is adopted and cross-device tested.
2. **Local databases rely on the OS sandbox.** The Matrix cache and outbox are
   not separately encrypted. A rooted or jailbroken device, or a full-device
   backup on a platform that permits one, can read them.
3. **No certificate pinning.** A device that trusts an attacker-supplied CA can
   intercept traffic. Pinning was not adopted because it complicates homeserver
   certificate rotation on a self-hosted deployment.
4. **No root or jailbreak detection**, and no screenshot suppression. Both are
   deterrents rather than controls and were out of MVP scope.
5. **The mobile number is unverified.** It is stored in private account data and
   labelled "not verified" in the interface. It must not be treated as an
   identity or recovery factor.
6. **About text and mobile number are private to their owner.** They are not
   published to other users, so no additional exposure exists today, but any
   future move to extended profiles would publish them and needs its own review.
7. **Reports are delivered to the homeserver's report endpoints.** Whoever
   operates the homeserver sees report contents. Moving to a dedicated
   moderation service, which `ReportRepository` already allows, would change
   that trust boundary and should be re-reviewed then.

## Recommended before public release

- Run the review again after push credentials are wired, since that introduces
  the first third-party services in the data path.
- Add a CI secret scan so the `.gitignore` additions are enforced rather than
  trusted.
- Complete the licensing review noted in [`architecture.md`](architecture.md);
  the Matrix Dart SDK and Synapse are AGPL-3.0-or-later.
- Test a full restore from an off-server backup, per
  [`operations.md`](operations.md). Backup integrity is a security property.
