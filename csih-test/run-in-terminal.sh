#!/bin/bash
# Steps that my sandbox can't run faithfully. Run from your own terminal:
#   bash ~/Projects/claude-sign-in-helper/csih-test/run-in-terminal.sh
# Everything is written under csih-test/; nothing reads or prints cookie values.
cd "$(dirname "$0")" || exit 1
APP="$PWD/dist-sdk26.5/Claude Sign-In Helper.app"
BIN="$APP/Contents/MacOS/ClaudeSignInHelper"

echo "== 3. self-tests (native arm64)"
"$BIN" --self-test > user-selftest-arm64.txt 2>&1; echo "exit=$?" | tee -a user-selftest-arm64.txt
tail -1 user-selftest-arm64.txt
echo "== 3. self-tests (x86_64 under Rosetta)"
/usr/bin/arch -x86_64 "$BIN" --self-test > user-selftest-x86_64.txt 2>&1; echo "exit=$?" | tee -a user-selftest-x86_64.txt
tail -1 user-selftest-x86_64.txt

echo "== 4a. Desktop signature"
{
CLAUDE_APP=/Applications/Claude.app; [ -d "$CLAUDE_APP" ] || CLAUDE_APP="$HOME/Applications/Claude.app"
codesign --verify --strict -R='identifier "com.anthropic.claudefordesktop" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW"' "$CLAUDE_APP" \
  && echo "Desktop matches helper's signing requirement" || echo "Desktop does NOT match helper's signing requirement"
codesign -dv "$CLAUDE_APP" 2>&1 | grep -E 'Identifier|TeamIdentifier'
} 2>&1 | tee user-4a.txt

echo "== 4b. --check-json (if a macOS prompt appears, note its exact wording)"
{ "$BIN" --check-json; echo "exit=$?"; } > user-4b.txt 2>&1
cat user-4b.txt

echo "== 5. previews (takes a few minutes)"
mkdir -p previews previews/logs
SCENES="welcome quit ready importing existing success opened verified unconfirmed permission backups backups-empty restored help confirm-import confirm-restore"
for lang in en ja zh-Hans fr; do
  for scene in $SCENES; do
    for mode in light dark; do
      out="$PWD/previews/$lang-$scene-$mode.png"
      flag=""; [ "$mode" = dark ] && flag="--dark"
      "$BIN" --render-preview "$out" --scene "$scene" $flag --scale 2 \
        -AppleLanguages "($lang)" -NSShowNonLocalizedStrings YES \
        >>"$PWD/previews/logs/$lang.log" 2>&1 || echo "FAILED $lang $scene $mode" | tee -a previews/logs/failures.txt
    done
  done
done
echo "previews: $(ls previews/*.png 2>/dev/null | wc -l | tr -d ' ') (expect 128)"
echo "== done"
