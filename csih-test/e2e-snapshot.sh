#!/bin/bash
# Usage: bash e2e-snapshot.sh before|after|after-restore
# Runs probes 4b, 4c and the 4d marker count; prints structure only, never cookie values.
label="${1:?usage: e2e-snapshot.sh before|after|after-restore}"
cd "$(dirname "$0")" || exit 1
out="e2e-$label.txt"
[ -e "$out" ] && { echo "$out already exists; pick another label" >&2; exit 1; }
BIN="$PWD/dist-sdk26.5/Claude Sign-In Helper.app/Contents/MacOS/ClaudeSignInHelper"
DB="$HOME/Library/Application Support/Claude/Cookies"
LOG="$HOME/Library/Logs/Claude/main.log"
{
echo "== $label $(date '+%Y-%m-%d %H:%M:%S')"
echo "== 4b"
"$BIN" --check-json; echo "exit=$?"
echo "== 4c"
stat -f 'owner=%Su mode=%Lp size=%z' "$DB"
sqlite3 -readonly "$DB" <<'SQL'
.headers on
SELECT key, value FROM meta;
SELECT group_concat(name, ', ') AS columns FROM (SELECT name FROM pragma_table_info('cookies') ORDER BY cid);
SELECT il.name AS index_name, il."unique", (SELECT group_concat(ii.name, ', ') FROM pragma_index_info(il.name) ii) AS index_columns FROM pragma_index_list('cookies') il;
PRAGMA journal_mode;
PRAGMA quick_check;
SELECT host_key, name, CAST(substr(encrypted_value, 1, 3) AS TEXT) AS enc_prefix, (value = '') AS plaintext_empty
  FROM cookies WHERE host_key IN ('claude.ai', '.claude.ai') ORDER BY host_key, name;
SQL
echo "== 4d"
[ -f "$LOG" ] && echo "main.log marker count: $(grep -c 'claude.ai account active and logged in' "$LOG")" || echo "main.log not found"
} > "$out" 2>&1
echo "saved $out"
