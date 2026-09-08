# Security and privacy

ZeroType sends recordings, prompts and dictionary entries to the configured speech provider. The default destinations are OpenAI and Google. Custom endpoints must use HTTPS and receive the same credentials and content. Only configure providers you trust; TLS does not make a provider trustworthy. Redirects are disabled so a provider cannot redirect an authenticated upload to another destination.

## Local storage

API keys and the history encryption key are held by `flutter_secure_storage` (Keychain on macOS and platform-protected storage on Windows). Secure storage failures stop migration or saving; there is no plaintext fallback. Existing preference keys are removed only after a verified secure write. Existing backups may still contain old plaintext keys; rotate keys previously used with older versions if those backups were exposed.

Transcripts and history audio use AES-256-GCM with a fresh nonce for every encryption. The encrypted JSON envelope is versioned; authentication failures are surfaced rather than silently replacing history. Existing `history.json` and referenced audio migrate on the next history access. The encrypted index is committed before plaintext legacy files are deleted. Migration only accepts regular audio files directly inside the app's history directory. Do not downgrade after migration: older versions cannot read encrypted history. Losing the OS vault key makes history unreadable. The History screen can still delete unreadable history.

Cumulative usage count/cost in `history_stats.json` remains unencrypted and contains no transcript, audio or API key. The prompt and custom dictionary remain ordinary local configuration and are sent to the provider.

Recording and playback temporarily require plaintext audio. New temporary files live in per-session directories (mode 0700 on macOS). Processing deletes temporary recordings in `finally`; playback deletes decrypted files on stop/completion/disposal. Stale app-owned temporary files and unreferenced history audio older than 24 hours are reclaimed during maintenance. This protects against casual disk inspection, not an attacker executing as the logged-in user. File deletion is not guaranteed secure erasure on SSDs, snapshots or backups.

Retention runs at startup, every 15 minutes while the app is running, and immediately after changing the retention setting. The default is seven days. The app must be running to perform cleanup; a corrupt or inaccessible vault/index can prevent automatic cleanup and is reported. Recording durations are clamped to 1–5 minutes.

## Cancellation and output

Cancelling an in-flight transcription cancels its HTTP request, ignores late responses and rolls back incomplete history. A new recording cannot reuse the recorder until pending work finishes cleanup. Temporary files are cleaned on errors and cancellation. Cancellation cannot retract bytes already received by a provider or undo text already pasted into another application. Transcription output goes to the foreground input and the system clipboard; clipboard history/sync may retain successful output. Avoid switching to sensitive destinations while waiting for transcription.

History playback uses a native audio player, not PowerShell or a command interpreter. The player only receives locally decrypted validated history audio.

## macOS permissions and signing

Microphone access supports recording. Accessibility supports global paste and Esc handling. Release App Sandbox remains disabled: global input injection and the existing AppleScript music integration require a separate compatibility/design review before sandboxing can be enabled. Do not interpret this change as a sandboxed application. Keychain Sharing entitlements are included for Debug/Profile and Release. Builds need a valid local signing configuration for the macOS Keychain; an unsigned/ad-hoc CI build is only a compilation check.

## Dependency and release verification

Commit `pubspec.lock` and use `flutter pub get --enforce-lockfile` for repeatable resolution. CI runs the security regression tests and macOS/Windows builds using a fixed Flutter version. These checks do not establish that an independently uploaded DMG/MSI matches this source. Release signing, notarization, installer provenance, and real-device permission/playback tests must be checked before distribution.
