# Contributing

Thanks for helping improve Claude Sign-In Helper. It's a small native macOS app (SwiftUI and AppKit) with no dependencies, built with a single script.

## Ground rules

- **Never commit or post real sign-in data.** That includes cookie values, session keys, tokens, Keychain passwords, backup folders, cookie databases, and raw Claude logs. `.gitignore` blocks the common file names, but please double-check your diff.
- **Test with synthetic data.** Don't run imports or restores against a real account just to try a change. Use `--self-test` and the preview renderer below.
- **Engine changes need tests.** Anything in `Core.swift` or `Engine.swift` should come with a matching self-test in `SelfTests.swift`.
- **Keep the promises in the README.** No network access, nothing read until the user asks, a backup before every change, and never overwriting an existing or newer Desktop sign-in.

## Build and test

Requires macOS 13 or later with Apple's Command Line Tools (`xcode-select --install`) or Xcode.

```bash
./build.sh                    # builds dist/Claude Sign-In Helper.app (universal, ad hoc signed)
./build.sh dist-2             # build.sh never overwrites; use a new folder for another build
"dist/Claude Sign-In Helper.app/Contents/MacOS/ClaudeSignInHelper" --self-test
```

`--self-test` runs 32 isolated tests using fabricated credentials and temporary files. They cover:

- Safari cookie parsing and the cases it must reject
- AES and PBKDF2 against independent test vectors
- Backup privacy, rollback, and restoring older manifests
- Preserving newer sessions, checksums, symbolic links, and redacted errors

For a quick read-only check of the current Mac, `--check-json` prints a status and the Desktop version, or a redacted error.

## Preview renderer

The app can render its own screens with demonstration data. It never touches real data:

```bash
BIN="dist/Claude Sign-In Helper.app/Contents/MacOS/ClaudeSignInHelper"
"$BIN" --render-preview /tmp/ready.png --scene ready --dark --scale 2 -AppleLanguages "(ja)"
```

- `--scene`:
  - Main screen: `welcome`, `quit`, `ready`, `importing`, `existing`, `success`, `opened`, `verified`, `unconfirmed`, `permission`
  - Sheets: `backups`, `backups-empty`, `restored`, `help`
  - Alerts: `confirm-import`, `confirm-restore`
- `--dark` renders the dark appearance. `--scale 2` renders at Retina resolution.
- `-AppleLanguages "(code)"` picks the language, for example `en`, `ja`, `zh-Hans`, or `fr`.
- The output file must not already exist. Rendering needs a logged-in macOS session.

The README screenshots in `docs/screenshots/` use these demonstration scenes, exported on macOS with native SwiftUI rendering at 4× resolution.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/Core.swift` | Safari cookie parsing, cookie encryption, and SQLite access |
| `Sources/Engine.swift` | Check, import, backup, restore, and verify operations |
| `Sources/SelfTests.swift` | The `--self-test` suite |
| `Sources/ViewModel.swift` | App state and actions, demonstration scenes, `localized(_:)` |
| `Sources/SignInPage.swift` | The main screen: step model (`SignInFlow`), wording, actions, progress dots |
| `Sources/BackupsPage.swift`, `Sources/HelpPage.swift` | The Backups and How it works sheets |
| `Sources/Views.swift` | Window content, sheet switching, and the confirmation alert wording |
| `Sources/Theme.swift` | Colors, fonts, the app mark, and button styles |
| `Sources/Window.swift` | The fixed-size main window |
| `Sources/Language.swift` | The Language menu's saved choice and restart |
| `Sources/main.swift` | Command-line modes, the preview renderer, and menus |
| `Resources/Info.plist` | Bundle identity, version, and supported languages |
| `Resources/<language>.lproj/` | Translations |
| `Tools/MakeIcon.swift` | Draws the app icon at build time |
| `docs/` | README icon and screenshots |

## Translations

All text lives in `Resources/<language>.lproj/Localizable.strings`. **The English text is the key**, and the value on the right is what the user sees:

```text
"Check this Mac" = "このMacを確認";
```

- **Fixed text** in SwiftUI's `Text`, `Button`, and `Label` is looked up automatically. Text built in code uses `String(localized:)`.
- **The engine's error and progress messages** stay in English in `Core.swift` and `Engine.swift`. The UI translates them with `localized(_:)` when it shows them, so every new engine message needs an entry in each language too.
- **Placeholders** must be kept: `%@` is text and `%lld` is a number.

**To add a language:**

1. Copy `Resources/en.lproj` to a new folder named with the language code, for example `Resources/de.lproj`, and translate the right-hand side.
2. Add the code to `CFBundleLocalizations` in `Resources/Info.plist`.
3. Add it to `AppLanguage.choices` in `Sources/Language.swift`, written in its own language (for example `Deutsch`).
4. Use the names macOS itself uses for System Settings, Privacy & Security, Full Disk Access, Keychain, and Finder in that language.
5. Build, then render the screens with `-AppleLanguages "(de)" -NSShowNonLocalizedStrings YES`. Any missing translation is logged and shown in capitals. Check that the text fits: the window is 440 × 480 points, and sheets must fit in the 452 points below the title bar.

## Design notes

- **One small fixed window (440 × 480).** Each state has a short serif headline, one or two sentences, one clay button that responds to Return, and at most two quiet text links.
- **Warm neutrals and a clay accent** in the spirit of Claude's own apps, with matching dark mode. Colors and button styles are in `Theme.swift`.
- **Keep three states distinct:** "already has a sign-in", "sign-in imported", and "Desktop reported a successful sign-in".
- **Confirmations use standard macOS alerts.**

## Pull request checklist

- [ ] `./build.sh` succeeds and `--self-test` passes
- [ ] New or changed text has entries in every `Localizable.strings` file
- [ ] Changed screens were checked with the preview renderer in light and dark mode
- [ ] No real cookies, backups, logs, or personal screenshots are included

## Releasing

1. Update the version in `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`) and `Format.version` in `Sources/Core.swift`, and add a section to `CHANGELOG.md`.
2. Build in a fresh folder and run the self-tests.
3. Zip the app and attach it to a GitHub release:

   ```bash
   ditto -c -k --keepParent "dist/Claude Sign-In Helper.app" "Claude-Sign-In-Helper-0.3.0.zip"
   ```

Builds are ad hoc signed and not notarized, so macOS asks people to approve the first launch. Maintainers can sign with their own Developer ID and notarize instead; no signing credentials are part of this repository.
