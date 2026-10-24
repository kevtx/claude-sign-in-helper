### Compatibility report: Claude Sign-In Helper 0.3.0 @ 476d405

**Machine:** Mac mini (Mac16,11), Apple M4 Pro, arm64; macOS 27.0 (26A428)
**Toolchain:** Apple Swift 6.4 (swiftlang-6.4.0.34.1); CLT 27.0.0.0.1788430756 / no Xcode installed
**Safari:** 27.0 · **Claude Desktop:** 3.6556.2, in /Applications

| Check | Result |
| --- | --- |
| Build (universal) | ❌ with the default macOS 27 SDK (see below) · ✅ with `SDKROOT=…/MacOSX26.5.sdk`, 2 warnings |
| `lipo -archs` | x86_64 arm64 |
| Self-tests, native (arm64) | 31/31 ✅ |
| Self-tests, x86_64 under Rosetta | 31/31 ✅ |
| No network symbols imported | ✅ |
| Desktop matches signing requirement | ✅ (`com.anthropic.claudefordesktop`, `Q6L2SF6YDW`) |
| `--check-json` | `desktop_session_exists` (Desktop signed in); `stopped` / `file_access` when Desktop was signed out and the command ran from Terminal |
| Cookie DB `meta.version` | 24 ✅ |
| `cookies` columns match | ✅ (all 20, same order) |
| Unique index matches | ✅ (`cookies_unique_index`, unique, exact column list) |
| `journal_mode` | delete ✅ |
| Encryption prefix on claude.ai rows | v10 ✅ (all rows, plaintext `value` empty) |
| Safari structure probe | skipped (no FDA) |
| Log marker present | yes (9 before testing; 11 → 12 across run 2; 12 → 15 across run 3; 16 → 17 across run 4) |
| Previews rendered | 128/128 |
| End-to-end import | runs 2 and 4: imported ✅, Desktop stayed signed in; run 4 showed "Sign-in confirmed" with the correct account · run 3 (reused Safari session): imported, then Desktop deleted the `sessionKey`; verification failed (see below) |
| Keychain prompt | **two** password prompts per import, both with Always Allow / Deny / Allow (wording below) |
| Restore | ❌ refused with "Desktop has a newer sign-in" while Desktop had no sign-in (run 3) |
| Release binary static check | not run |

**Build on macOS 27 with Command Line Tools only**

`./build.sh` fails at compile time against the default macOS 27 SDK:

```
Sources/BackupsPage.swift:5:24: error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
Sources/BackupsPage.swift:28:113: error: cannot assign to property: 'self' is immutable
Sources/BackupsPage.swift:87:40: error: cannot assign to property: 'self' is immutable
```

In the macOS 27 SDK, SwiftUI's `@State` is declared as an external macro (`#externalMacro(module: "SwiftUIMacros", type: "StateMacro")`). CLT 27.0 ships only `libObservationMacros` and `libSwiftMacros` in `usr/lib/swift/host/plugins`, so the macro can't expand. The README's "Command Line Tools are enough" doesn't hold on this setup; Xcode was not available to compare.

Building with the macOS 26.5 SDK (also bundled with CLT 27.0) works:

```
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh <fresh-folder>
```

That build produces 2 identical linker warnings, both from the x86_64 slice:

```
warning: ignoring file '/Library/Developer/CommandLineTools/usr/lib/swift/macosx/libswiftCompatibilityPacks.a': fat file missing arch 'x86_64', file has 'arm64,arm64e'
```

The x86_64 slice still passes all 31 self-tests under Rosetta. Every result in this report comes from that 26.5 SDK build.

**Build inspection**

- Ad hoc signature, hardened runtime (`flags=0x10002(adhoc,runtime)`), identifier `local.claude-signin-helper`; `codesign --verify --deep --strict` OK.
- Linked: system frameworks only (AppKit, Combine, CoreFoundation, CoreGraphics, CryptoKit, Foundation, Security, SwiftUI), `libsqlite3`, `libobjc` and the Swift runtime.
- `nm -u` network-symbol check: no network symbols imported.

**Desktop cookie database (read-only, structure only)**

- `meta`: `version` 24, `last_compatible_version` 24, `mmap_status` -1.
- File: owner = current user, mode 600.
- `PRAGMA quick_check`: ok, both before and after the import.
- The cookie names below come from a Desktop that was signed in normally, before testing.
- `claude.ai` cookie names while signed in: `CH-prefers-color-scheme`, `__cf_bm`, `__ssid`, `__stripe_mid`, `_fbp`, `_gcl_au`, `ajs_anonymous_id`, `cf_clearance`, `intercom-device-id-<id>`, `intercom-session-<id>`, `lastActiveOrg`, `routingHint`, `sessionKey`, `sessionKeyLC`, `user-sidebar-visible-on-load`, `_dd_s_v2`, `activitySessionId`, `anthropic-device-id`.
- No `sessionKeyV2` or `sessionKeyV3`. `sessionKeyLC` is present; the app ignores it today, but it may be worth knowing about.

**End-to-end import**

All runs used the GUI app built from source (26.5 SDK), with Desktop signed out in its own UI and quit with ⌘Q beforehand. (An earlier attempt is excluded: no helper backup was created, so Desktop was most likely signed in directly.)

**Run 2: success**

- Before: no `sessionKey` row. `--check-json` from Terminal returned `file_access`, as expected while Terminal lacks access to Safari's container.
- After:
  - `--check-json` returns `desktop_session_exists`.
  - `sessionKey` is the only new `claude.ai` row, with prefix `v10`.
  - Schema, unique index, `journal_mode` and `quick_check` are unchanged.
  - One backup was created.
  - The log marker went from 11 to 12.
- Two Keychain password prompts appeared (see run 3 for the wording).

**Run 3: screens and prompts, as observed**

1. "Bring your Safari sign-in to Claude Desktop" → **Check this Mac**
2. "macOS needs your permission" → **Open Full Disk Access**. No macOS "access data from other apps" prompt appeared; the helper went straight to its own permission screen.
3. After granting Full Disk Access, the app had to be relaunched, which returned to screen 1. **Check this Mac** then went on to screen 4.
4. "Ready to import" → **Import sign-in…**
5. Standard alert "Import your Safari sign-in? …" with **Cancel** / **Import**
6. macOS Keychain prompt: *"Claude Sign-In Helper wants to use your confidential information stored in "Claude Safe Storage" in your keychain."* Password field; buttons **Always Allow** / **Deny** / **Allow**; Allow chosen.
7. A second macOS Keychain prompt straight after: *"Claude Sign-In Helper wants to access key "Claude Safe Storage" in your keychain."* Password field; buttons **Always Allow** / **Deny** / **Allow**; Allow chosen.
8. "Sign-in imported" → **Open Claude** (Desktop opened)
9. "Confirm the sign-in" → **Verify sign-in**. Verification failed.

Then **Backups → Restore…** was refused with "Desktop has a newer sign-in". There was no way to override it.

**Run 3: what the files show**

- One backup was created, so the helper did write.
- After Desktop opened, `sessionKey` was gone again. The `claude.ai` rows were identical to the signed-out "before" state, and the log marker still went from 12 to 15.
- Schema, index, `journal_mode` and `quick_check` were unchanged.
- **Likely cause, supported by run 4:** run 2 put Safari's session into Desktop, so both shared one server session. Signing out of Desktop before run 3 probably ended that session for Safari too, but Safari's cookie file kept the dead cookie. The helper validates cookies only locally (expiry, flags), so it imported a revoked session, and Desktop dropped it on its first server contact. Run 4, after a fresh Safari sign-in, worked normally.
- So after an import, signing out of either app likely signs out the other, and a later import from the same Safari cookie silently fails. That may be worth a sentence in the README and on the "Not confirmed yet" screen ("sign in to Claude in Safari again, then retry").
- **Verification:** `verify()` returns false as soon as Desktop has no `sessionKey` (`hasLogin()`), so a server-rejected session shows as a failed verification. That's correct, but the screen can't tell the user why.
- **Restore message is misleading:** `restore()` refuses whenever `fingerprint()` of the `sessionKey` / `lastActiveOrg` / `anthropic-device-id` rows differs from the import-time fingerprint. Desktop *deleting* the session changes the fingerprint too, so the user sees "Desktop has a newer sign-in" when Desktop has no sign-in at all. Refusing is safe here, since the backup equals the signed-out state anyway, but the wording should distinguish "Desktop changed or removed the imported session" from "Desktop has a newer sign-in".

**Run 4: success with a fresh Safari session**

- Before: signed out of claude.ai in Safari and signed in again, which starts a new session. Then signed out of Desktop and quit it with ⌘Q.
- Screens: "Bring your Safari sign-in to Claude Desktop" → "Ready to import". With Full Disk Access already granted, there was no permission screen. Then the "Import your Safari sign-in?" alert, the same two Keychain prompts as run 3, "Sign-in imported", and "Confirm the sign-in".
- **Verify sign-in** showed "Sign-in confirmed". Desktop showed the correct account and was still signed in after reopening.
- Files:
  - `sessionKey` present as v10.
  - `--check-json` returns `desktop_session_exists`.
  - Log marker went from 16 to 17.
  - Schema, index, `journal_mode` and `quick_check` unchanged.
  - One backup created.

**Keychain prompts**

macOS asked twice per import, with the two different wordings shown in run 3, steps 6 and 7. The code reads the key once (`CookieCrypto.keyFromKeychain`, a single `SecItemCopyMatching` call), so both prompts come from macOS. This is plausibly one prompt for the item's access list and one for its partition list, since the source build is ad hoc signed with no team ID; that's unconfirmed. The help text and README describe a single prompt, so mentioning that two can appear would avoid confusion.

**Full Disk Access**

On macOS 27 the GUI app could not read Safari's cookies until it was given Full Disk Access, and it needed a relaunch afterwards. No system prompt offered access; the helper's own permission screen was the only guidance.

**Translation and layout issues**

- fr / help / light + dark: the help text is taller than the 440 pt sheet and is cut off mid-sentence at "Safari n'est pas modifié". It's in a `ScrollView`, so it's reachable, but nothing visibly shows there's more.
- ja / help / light + dark: same overflow; the 制限事項 heading sits at the bottom edge with its text hidden. en and zh-Hans fit.
- ja / confirm-import / light + dark: the title wraps and leaves 「か？」 alone on its second line.
- fr / backups, restored / light + dark: dates render as "12 oct. 2026 à 8:00 AM", a French date with an English 12-hour time. Probably the region setting leaking through, since the preview overrides only the language (`formatted(date:time:)` follows `Locale.current`). Low confidence.
- all languages / unconfirmed: "Backups" appears twice, as a secondary link under the button and again in the footer.
- No missing-translation warnings in any language's log, no ALL-CAPS fallback strings, no overlaps. Every sheet fits: the tallest is 440 pt, within 452. In dark mode, secondary grey links are a little low-contrast but readable.

**Other findings**

- `build.sh` creates its temp folder with `mktemp -d /private/tmp/claude-native-build.XXXXXX`, a fixed path that ignores `$TMPDIR`. That fails in sandboxed shells that can only write under `$TMPDIR`. Low priority.

_All data collected with the methods in CONTRIBUTING.md plus read-only structural probes. No cookie values, tokens, Keychain secrets or raw logs are included._
