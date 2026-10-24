#!/bin/bash
# Requires Apple's Command Line Tools or Xcode. The finished app needs neither.
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_dist="${1:-$task_root/dist}"
task_tmp="${TMPDIR:-/private/tmp}"
task_build="$(mktemp -d "${task_tmp%/}/claude-native-build.XXXXXX")"
trap 'rm -rf "$task_build"' EXIT
task_finalapp="$task_dist/Claude Sign-In Helper.app"
if [[ -e "$task_finalapp" ]]; then
  printf '%s\n' 'The destination app already exists. Choose an empty output directory.' >&2
  exit 1
fi
task_app="$task_build/Claude Sign-In Helper.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
for task_arch in x86_64 arm64; do
  xcrun swiftc -O -swift-version 5 -module-name ClaudeSignInHelper \
    -file-prefix-map "$task_root=." -debug-prefix-map "$task_root=." -module-cache-path "$task_build/modules" \
    -target "$task_arch-apple-macosx13.0" "$task_root"/Sources/*.swift \
    -o "$task_build/ClaudeSignInHelper-$task_arch"
done
xcrun lipo -create "$task_build/ClaudeSignInHelper-x86_64" "$task_build/ClaudeSignInHelper-arm64" \
  -output "$task_app/Contents/MacOS/ClaudeSignInHelper"
xcrun swiftc -module-cache-path "$task_build/modules" "$task_root/Tools/MakeIcon.swift" -o "$task_build/make-icon"
"$task_build/make-icon" "$task_build/AppIcon.iconset"
iconutil -c icns "$task_build/AppIcon.iconset" -o "$task_app/Contents/Resources/AppIcon.icns"
cp "$task_root/Resources/Info.plist" "$task_app/Contents/Info.plist"
# Translations: one <language>.lproj folder per language, each with Localizable.strings.
plutil -lint -s "$task_root"/Resources/*.lproj/*.strings
cp -R "$task_root"/Resources/*.lproj "$task_app/Contents/Resources/"
cp "$task_root/LICENSE" "$task_app/Contents/Resources/LICENSE"
cp "$task_root/README.md" "$task_app/Contents/Resources/README.md"
chmod 755 "$task_app/Contents/MacOS/ClaudeSignInHelper"
codesign --force --sign - --options runtime "$task_app"
codesign --verify --deep --strict "$task_app"
mkdir -p "$task_dist"
mv "$task_app" "$task_finalapp"
printf 'Built %s\n' "$task_finalapp"
