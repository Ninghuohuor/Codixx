# Codixx Manual Test Checklist

Use a temporary macOS user profile or a disposable `HOME` when possible. Never use an auth snapshot you cannot recover.

## First Launch

- [ ] Launch without `~/.codex`; app opens as a menu bar extra and shows a readable degraded/empty state.
- [ ] Launch with `~/.codex/auth.json`; current account can be detected after saving the account.
- [ ] Launch with `~/.codex/state_5.sqlite` missing; usage area shows no crash and reports degraded usage state.
- [ ] Launch while another Codixx instance is running; second instance exits and the existing app is activated.

## Account Storage

- [ ] Save current account with alias `Main`; `~/Library/Application Support/Codixx/accounts.json` contains metadata only, not raw auth JSON.
- [ ] Save the same auth again; duplicate fingerprint is rejected and the UI shows the error.
- [ ] Deny or break Keychain access; app shows a recoverable Keychain error and does not write partial metadata.

## Manual Switching

- [ ] Save two accounts.
- [ ] Switch from account A to account B.
- [ ] Confirm `~/.codex/auth.json` matches B and a backup exists under `~/Library/Application Support/Codixx/backups`.
- [ ] Confirm `switch_audit.jsonl` records a success event with aliases and backup path, without raw tokens.
- [ ] Force validation failure with a corrupted snapshot; app rolls back to the previous auth and writes failure plus rollback audit events.

## Automatic Switching

- [ ] Add a fresh JSONL rate-limit observation at 92%; app warns at 80% at most once per 5-hour window.
- [ ] Add a fresh JSONL rate-limit observation at 93%; app automatically switches to the best enabled candidate.
- [ ] Disable all candidate accounts and repeat the 93% observation; app enters protection mode and sends one protection notification.
- [ ] Set the current account quota to stale; app does not auto-switch on stale quota.
- [ ] Set disk space under 50 MB in the test environment; app should not attempt unsafe auth replacement and must surface a recoverable error.

## Usage Display

- [ ] Confirm total tokens are read from `state_5.sqlite`.
- [ ] Confirm top thread ranking orders by token count.
- [ ] Confirm current thread is active only when updated within 10 minutes.
- [ ] Replace `state_5.sqlite` with an incompatible schema; app remains open and shows degraded usage state.
- [ ] Lock `state_5.sqlite`; app retries and then shows degraded state if the lock remains.

## Session Parsing

- [ ] Add valid `rate_limits` JSONL lines under `~/.codex/sessions`; quota updates on refresh.
- [ ] Add malformed JSONL before a valid line; parser skips malformed input and still consumes the valid observation.
- [ ] Truncate a session file; cursor resets and new observations are not skipped.
- [ ] Add archived JSONL under `~/.codex/archived_sessions`; parser reads direct archived files.

## Lifecycle

- [ ] Open the menu repeatedly; refreshes are throttled and the UI remains responsive.
- [ ] Put the Mac to sleep and wake it; timers resume and the app refreshes.
- [ ] Modify `~/.codex/auth.json` externally; app refreshes current account state.
- [ ] Toggle notifications off; optional quota warnings stop while safety notifications still appear.
- [ ] Quit from the footer power button; process exits and releases `codixx.pid`.

## Packaging

- [ ] Run `bash scripts/package_app.sh`.
- [ ] Confirm `build/Codixx.app/Contents/MacOS/Codixx` exists and is executable.
- [ ] Confirm `build/Codixx.app/Contents/Info.plist` includes `LSUIElement=true`.
- [ ] Launch `build/Codixx.app`; no Dock icon appears and the menu bar item is available.
