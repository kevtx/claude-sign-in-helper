# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small native macOS app (SwiftUI + AppKit, macOS 13+, no dependencies, no Xcode project) that copies the Claude `sessionKey`/`lastActiveOrg`/`anthropic-device-id` cookies from Safari's `Cookies.binarycookies` into Claude Desktop's Chromium cookie database (`~/Library/Application Support/Claude/Cookies`), encrypted with the "Claude Safe Storage" Keychain key.

## Commands

```bash
./build.sh                     # universal build -> dist/Claude Sign-In Helper.app (ad hoc signed)
./build.sh dist-2              # build.sh refuses to overwrite an existing app; use a fresh folder
# build.sh puts its temp folder under $TMPDIR (falls back to /private/tmp)

BIN="dist/Claude Sign-In Helper.app/Contents/MacOS/ClaudeSignInHelper"
"$BIN" --self-test             # 32 synthetic-data tests; prints PASS/FAIL per test, nonzero exit on failure
"$BIN" --check-json            # read-only check of this Mac: status + Desktop version or a redacted error
"$BIN" --render-preview /tmp/x.png --scene ready --dark --scale 2 -AppleLanguages "(ja)"
```

- There is no test filter: tests are `test("name") { ... }` closures inside `runSelfTests()` in `Sources/SelfTests.swift`, and `--self-test` runs all of them. To iterate on one, temporarily comment out others or just read its PASS/FAIL line.
- `csih-test/e2e-snapshot.sh before|after|after-restore` is a manual, read-only probe of the *real* Desktop cookie DB and log (structure and counts only, never values). It expects a build in `csih-test/dist-sdk26.5/` and refuses to overwrite an existing `e2e-<label>.txt`. The real import between snapshots is done by a human, not by you.
- There is no linter. `build.sh` runs `plutil -lint` on every `Localizable.strings`, so a malformed translation fails the build.
- `--render-preview` scenes: `welcome`, `quit`, `ready`, `importing`, `existing`, `success`, `opened`, `verified`, `unconfirmed`, `permission`, `backups`, `backups-empty`, `restored`, `help`, `confirm-import`, `confirm-restore`. The output file must not already exist, and rendering needs a logged-in GUI session. Add `-NSShowNonLocalizedStrings YES` to surface missing translations (shown in capitals).

## Architecture

- **`Core.swift`** – low-level, UI-free primitives: `Format` (version, Desktop bundle ID/team ID, allowed domains/cookie names, the exact Chromium `cookies` column list and selection SQL), `LocalPaths` (all filesystem locations, discovered for the real user; refuses root), `safeRead` (no symlinks, size limits), `SafariReader.parse` (binary cookie parser that rejects anything ambiguous/expired/non-root/unprotected), `CookieCrypto` (PBKDF2 + AES-CBC, hostname-bound values, Keychain lookup), and `CookieDatabase` (SQLite wrapper with schema validation, integrity check, key verification against an existing encrypted cookie, backup).
- **`Engine.swift`** – `SessionEngine` composes Core into user-level operations: `inspect`, `importCookies`/`repair`, `makeBackup` + `BackupManifest` (checksummed, 0700/0600), `backups`, `restore` (keeps unrelated cookies, refuses if Desktop has a newer login), `verify` (reads Desktop's `main.log`). `OperationLock` serializes operations; Desktop must be closed and its code signature is checked first.
- **Errors** – everything throws `HelperFailure(code:title:detail:)`; `readableFailure` redacts unexpected errors. Engine messages stay in English and the UI translates them with `localized(_:)`.
- **UI** – `ViewModel.swift` holds state (`FlowStage`, `HelperSheet`), runs engine calls, and also defines the demonstration scenes used by `--render-preview`. `SignInPage.swift` maps state to the main screen (`SignInFlow` step model, wording, actions). `Views.swift` switches sheets and holds confirmation-alert wording. `Theme.swift` holds all colors/fonts/button styles.
- **`main.swift`** – dispatches CLI modes (`--self-test`, `--check-json`, `--render-preview`) before launching the GUI; also builds menus.
- **Self-tests** construct fake Safari binary cookie files and temp Chromium databases in-process (`record`, `binary`, `cookie` helpers at the top of `SelfTests.swift`) and run the real engine against them with a fabricated key.

## Rules from CONTRIBUTING.md

- Never commit or print real sign-in data (cookie values, keys, Keychain passwords, backups, cookie DBs, raw Claude logs). Don't run imports/restores against a real account to test a change; use `--self-test` and the preview renderer.
- Any change to `Core.swift` or `Engine.swift` needs a matching self-test. Update the "32 self-tests" count in README/CONTRIBUTING if it changes.
- Keep the README promises: no network access, nothing read until the user asks, a backup before every change, never overwrite an existing or newer Desktop sign-in.
- **Translations:** English text is the key in `Resources/<lang>.lproj/Localizable.strings` (en, fr, ja, zh-Hans). Every new UI string *and* every new engine message needs an entry in every language; keep `%@`/`%lld` placeholders. Adding a language also means `CFBundleLocalizations` in `Resources/Info.plist` and `AppLanguage.choices` in `Language.swift`.
- **Layout limits:** fixed 440 × 480 window; sheets must fit in the 452 pt below the title bar. Check changed screens in light and dark with the preview renderer.
- **Design:** each state has a short serif headline, one or two sentences, one clay button bound to Return, at most two quiet text links. Keep "already has a sign-in", "sign-in imported", and "Desktop reported a successful sign-in" distinct. Confirmations use standard macOS alerts.
- **Releasing:** bump `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` *and* `Format.version` in `Core.swift`, add a `CHANGELOG.md` section, build in a fresh folder, run self-tests, then `ditto -c -k --keepParent "dist/Claude Sign-In Helper.app" "Claude-Sign-In-Helper-<version>.zip"`.
