#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
assets_root="${1:-$repo_root/target/github-release}"
output_path="${2:-$assets_root/clipplus-update.json}"
version_file="$repo_root/VERSION"

if [[ ! -f "$version_file" ]]; then
    echo "Missing VERSION file: $version_file" >&2
    exit 2
fi

version="$(tr -d '[:space:]' < "$version_file")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be MAJOR.MINOR.PATCH, got: $version" >&2
    exit 2
fi

if [[ ! -d "$assets_root" ]]; then
    echo "Missing assets directory: $assets_root" >&2
    exit 2
fi

mkdir -p "$(dirname "$output_path")"

python3 - "$assets_root" "$output_path" "$version" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

assets_root = Path(sys.argv[1])
output_path = Path(sys.argv[2])
version = sys.argv[3]
tag = f"v{version}"
repo = "nicelnicel/ClipPlus"
required_names = [
    "ClipPlus-macOS.dmg",
    "ClipPlus-Windows-x64-full.exe",
    "ClipPlus-Windows-x64-runtime-dependent.exe",
]

def find_required_asset(name: str) -> Path:
    matches = [path for path in assets_root.rglob(name) if path.is_file()]
    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one {name} under {assets_root}, found {len(matches)}")
    return matches[0]

assets = []
for name in required_names:
    path = find_required_asset(name)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assets.append({
        "name": name,
        "browser_download_url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
        "digest": f"sha256:{digest}",
        "size": path.stat().st_size,
    })

manifest = {
    "tag_name": tag,
    "draft": False,
    "prerelease": False,
    "assets": assets,
}

temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
temporary_path.write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
os.replace(temporary_path, output_path)
print(f"Wrote update manifest: {output_path}")
PY
