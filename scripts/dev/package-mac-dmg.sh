#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="$repo_root/target/macos-build.noindex/ClipPlus.app"
dmg_dir="$repo_root/target/macos"
dmg_path="$dmg_dir/ClipPlus-macOS.dmg"

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil is required to package a macOS DMG." >&2
    exit 1
fi

if [[ ! -d "$app_dir" ]]; then
    "$repo_root/scripts/dev/package-mac-app.sh"
fi

mkdir -p "$dmg_dir"
rm -f "$dmg_path"
hdiutil create \
    -volname "ClipPlus" \
    -srcfolder "$app_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"
hdiutil verify "$dmg_path" >/dev/null

echo "ClipPlus macOS DMG: $dmg_path"
