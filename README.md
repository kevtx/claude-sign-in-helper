<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="Claude Sign-In Helper app icon">

# Claude Sign-In Helper

**Bring the Claude sign-in you already have in Safari to the Claude Desktop app.**

A tiny, native macOS utility for when Claude works in Safari, but the Desktop app can't finish signing in.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1d1d1f?logo=apple&logoColor=white)](#requirements)
[![Universal](https://img.shields.io/badge/universal-Apple%20silicon%20%2B%20Intel-555555)](#requirements)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white)](Sources)
[![License: MIT](https://img.shields.io/badge/license-MIT-3a7bd5)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/hibari233/claude-sign-in-helper?color=C15F3C&label=release)](https://github.com/hibari233/claude-sign-in-helper/releases/latest)

[Download](#download) · [How to use](#how-to-use) · [Privacy & safety](#privacy--safety) · [FAQ](#faq) · [Build from source](#build-from-source)

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/hero-dark.png">
  <img src="docs/screenshots/hero-light.png" width="880" alt="Claude Sign-In Helper's three main screens: Check this Mac, Ready to import, and Sign-in confirmed">
</picture>

</div>

## Why

Claude Desktop sometimes can't complete a sign-in that works fine in a browser. A common example is when the login email never arrives at an Apple **Hide My Email** (private relay) address. If Claude already works in Safari on the same Mac, this helper copies that existing session into Claude Desktop's own encrypted cookie store, so Desktop can pick up the account you're already signed in to.

It works entirely on your Mac. It doesn't create a new sign-in, it can't recover an account that's signed out everywhere, and it doesn't use Claude Code CLI tokens.

## Features

- **One small window, one step at a time.** Check this Mac, import the sign-in, open Claude, confirm. Each screen has a single main button, and Return activates it.
- **Safe by default.** Opening the app reads nothing, and checking only reads. A private backup is saved before every import, and you can undo an import from **Backups**.
- **Respects what's already there.** It never overwrites an existing Desktop sign-in, and an undo never replaces a newer one.
- **Fully local.** No network requests, no telemetry. Cookie values, tokens, and passwords are never shown or logged. Your Mac password goes only into macOS's own Keychain prompt.
- **Checks before it writes.** It verifies that Claude Desktop is the official, Anthropic-signed app and that the encryption key matches before changing anything. Every change happens in a single transaction that's rolled back if anything fails.
- **Honest results.** "Sign-in imported" and "Desktop reported a successful sign-in" are separate steps, because a copied session isn't proof that the server accepted it.
- **Native and tiny.** SwiftUI and AppKit, no dependencies, universal binary, light and dark mode.
- **Four languages.** English, 日本語, 简体中文, and Français, with a language menu built in.

## Download

1. Download the latest `Claude-Sign-In-Helper-<version>.zip` from [**Releases**](https://github.com/hibari233/claude-sign-in-helper/releases/latest), unzip it, and move **Claude Sign-In Helper** to your Applications folder.
2. Open it. The first time, macOS will say it can't verify the app, because this preview is ad hoc signed and **not notarized by Apple**. Go to **System Settings ▸ Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to Claude Sign-In Helper. On macOS 13 and 14 you can instead Control-click the app and choose **Open**.

> [!IMPORTANT]
> Please don't turn off Gatekeeper to run it. If you'd rather not open an unnotarized download, [build it from source](#build-from-source). It takes about a minute and needs only Apple's free command line tools.

### Requirements

- macOS 13 Ventura or later, on Apple silicon or Intel
- The official [Claude Desktop](https://claude.ai/download) app in `/Applications` or `~/Applications`
- A working Claude sign-in in Safari's default profile, on the same Mac and the same macOS account

## How to use

1. **Prepare.** Make sure Claude works in Safari. Open Claude Desktop once, then quit it with **⌘Q**.
2. **Check this Mac.** The helper finds Claude Desktop and your Safari sign-in. Checking only reads. If Desktop already has a saved sign-in, the helper leaves it alone and offers **Open Claude** instead.
3. **Import sign-in…** Confirm, and a private backup is saved first. If macOS asks to allow access to **Claude Safe Storage**, choose **Allow**, and type your Mac password only in that macOS dialog.
4. **Open Claude, then Verify sign-in.** The helper looks for Claude Desktop's own report of a successful sign-in. Check that Claude shows the account you expect.

> [!TIP]
> If macOS blocks access to Safari's data, the helper tells you and offers **Open Full Disk Access**. Turn on Claude Sign-In Helper there, then quit and reopen it. Only grant access if you trust the app. You can turn it off again when you're done.

<div align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/details-dark.png">
  <img src="docs/screenshots/details-light.png" width="880" alt="The Full Disk Access screen, the Backups sheet, and the How it works sheet">
</picture>
</div>

## Privacy & safety

|  | What the helper does |
| --- | --- |
| **Reads** | Safari's cookie file, keeping only `sessionKey`, `lastActiveOrg`, and `anthropic-device-id` for exactly `claude.ai` or `.claude.ai`. Also Claude Desktop's cookie database and its local log (to confirm the sign-in), plus the **Claude Safe Storage** Keychain item, which macOS asks you about. |
| **Writes** | Only those Claude cookies in Claude Desktop's cookie database, encrypted in Desktop's existing format. Private backups go in `~/Library/Application Support/Claude Sign-In Helper/Backups`. |
| **Never** | Makes network requests or sends telemetry. Shows or logs cookie values, tokens, or passwords. Changes Safari. Overwrites an existing Desktop sign-in. Force-quits apps. Runs as root. |

<details>
<summary><b>Safeguards</b></summary>

- Verifies Claude Desktop's code signature and Anthropic's signing identity before reading or writing its data.
- Checks the Keychain key against an existing encrypted Desktop cookie before writing, so a wrong key can't corrupt anything.
- Writes in one SQLite transaction, verifies the result, and rolls back on any failure.
- Refuses symbolic links, files owned by another account, unfamiliar database schemas, and ambiguous or expired sessions, and stops without changing anything.
- Shows only redacted errors: no raw logs or credentials.
- Covered by 32 self-tests that use only fabricated credentials and temporary files.

</details>

<details>
<summary><b>Backups and undo</b></summary>

- Before every import, the helper copies Desktop's cookie database and writes a manifest with checksums. Backup folders are readable only by your account (`0700`), and files are `0600`.
- **Backups** (⌘B) lists each import. **Restore…** puts back the original Claude cookies and keeps unrelated cookies. It saves a checkpoint first, and it stops if Desktop has a newer sign-in.
- Restoring isn't a full sign-out. It doesn't revoke server sessions or remove tokens Desktop created later.
- Backups contain sensitive data. Keep them private and don't share them.
- Backups made by the earlier Python version of this helper can still be restored.

</details>

<details>
<summary><b>What's supported</b></summary>

**Supported:** your own macOS account (no `sudo`); the official Claude Desktop in `/Applications/Claude.app` or `~/Applications/Claude.app`; Safari's default cookie store with exactly one unexpired, Secure, HttpOnly root `sessionKey`; Chromium cookie database version 24.

**Not supported** (the helper stops safely without changing anything): other browsers, other Safari profiles, multiple sessions, `sessionKeyV2` and `sessionKeyV3`, unfamiliar databases, modified Desktop apps, and expired sessions. The helper may stop working if Safari or Claude change how they store sign-ins.

</details>

## FAQ

<details>
<summary><b>Is this an official Anthropic app?</b></summary>

No. It's an independent open-source utility, not affiliated with or endorsed by Anthropic or Apple. For official help, see [Anthropic's sign-in article](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account).

</details>

<details>
<summary><b>Does it send my data anywhere?</b></summary>

No. It makes no network requests and has no telemetry. Everything happens on your Mac. Opening Claude or the support article are separate actions handled by macOS.

</details>

<details>
<summary><b>Why does it need Full Disk Access?</b></summary>

Safari keeps its cookies in a protected location. macOS only lets an app read them if you allow it under **Privacy & Security ▸ Full Disk Access**. You only need this if the check reports that access is blocked, and you can turn it off afterward.

</details>

<details>
<summary><b>Why does macOS ask about "Claude Safe Storage"?</b></summary>

Claude Desktop encrypts its cookies with a key stored in your Keychain under that name. The helper needs it to write your session in Desktop's format. Choose **Allow**. macOS may ask twice, with slightly different wording; choose **Allow** both times. If macOS asks for a password, it's your Mac login password, typed into macOS's own dialog. The helper has no password field.

</details>

<details>
<summary><b>It says "Not confirmed yet". What now?</b></summary>

Claude Desktop may still be loading. Wait a moment and choose **Verify again**. If Claude asks you to sign in again, the server may have rejected the copied session. You can undo the import from **Backups**.

</details>

<details>
<summary><b>I'm signed out of Claude everywhere. Can it help?</b></summary>

No. It only copies a sign-in that already works in Safari on the same Mac. A sign-in that exists only on your iPhone can't be transferred.

</details>

## Build from source

You need Apple's Command Line Tools (`xcode-select --install`) or Xcode. There are no packages to install.

With Command Line Tools 27 and its macOS 27 SDK, the build fails with `plugin for module 'SwiftUIMacros' not found`. Build against the macOS 26.5 SDK that ships alongside it instead:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
```

```bash
git clone https://github.com/hibari233/claude-sign-in-helper.git
cd claude-sign-in-helper
./build.sh
open "dist/Claude Sign-In Helper.app"
```

`build.sh` compiles a universal (Apple silicon + Intel) app, generates the icon, bundles the translations, and signs it ad hoc. It never overwrites an existing build; pass another folder to build again (for example, `./build.sh dist-2`). To run the self-tests, which use only synthetic data:

```bash
"dist/Claude Sign-In Helper.app/Contents/MacOS/ClaudeSignInHelper" --self-test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout, the preview renderer, translations, and releasing.

## Project status

This is a **preview** (0.3.0). The transfer method has worked on a real Intel Mac, and the native app's import and restore engine is covered by 32 self-tests that use synthetic data. The universal build includes Apple silicon, but that hasn't been independently tested yet, and neither has the native app's interactive Keychain prompt. Reports are very welcome. See [CHANGELOG.md](CHANGELOG.md) for what's new.

## Contributing

Issues and pull requests are welcome, especially testing on Apple silicon and new translations. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

> [!CAUTION]
> Never post cookie values, session keys, tokens, Keychain passwords, backups, or raw logs in an issue. To report a security problem, follow [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Claude is a trademark of Anthropic, PBC. macOS and Safari are trademarks of Apple Inc. This project isn't affiliated with or endorsed by either company. It changes Claude Desktop's local cookie store, so use it at your own risk; it always keeps a backup first.

<details>
<summary>References</summary>

- [Anthropic: Log in to your Claude account](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)
- [Apple: Manage apps that use Sign in with Apple](https://support.apple.com/en-us/102571)
- [Apple Security: SecItemCopyMatching](https://developer.apple.com/documentation/security/secitemcopymatching(_:_:))
- [SQLite: Opening a database and NOFOLLOW](https://sqlite.org/c3ref/open.html)
- [Chromium cookie storage implementation](https://chromium.googlesource.com/chromium/src/+/HEAD/net/extras/sqlite/sqlite_persistent_cookie_store.cc)

</details>
