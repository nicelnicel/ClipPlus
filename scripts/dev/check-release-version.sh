#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 vMAJOR.MINOR.PATCH" >&2
    exit 2
fi

release_tag="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version_file="$repo_root/VERSION"

if [[ ! -f "$version_file" ]]; then
    echo "Missing VERSION file: $version_file" >&2
    exit 1
fi

version="$(tr -d '[:space:]' < "$version_file")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be MAJOR.MINOR.PATCH, got: $version" >&2
    exit 1
fi

if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release tag must be vMAJOR.MINOR.PATCH, got: $release_tag" >&2
    exit 1
fi

if [[ "$release_tag" != "v$version" ]]; then
    echo "Release tag $release_tag does not match VERSION $version. Run ./scripts/dev/bump-version.sh ${release_tag#v} before releasing." >&2
    exit 1
fi

python3 - "$repo_root" "$version" <<'PY'
from pathlib import Path
import re
import sys

repo_root = Path(sys.argv[1])
version = sys.argv[2]
assembly_version = f"{version}.0"
workspace_packages = {
    "clipplus-cli",
    "clipplus-core",
    "clipplus-crypto",
    "clipplus-diagnostics",
    "clipplus-discovery",
    "clipplus-ffi",
    "clipplus-transport",
}

def require_contains(path: Path, needle: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"{path} does not contain expected text: {needle}")

def require_regex(path: Path, pattern: str) -> None:
    text = path.read_text(encoding="utf-8")
    if re.search(pattern, text, flags=re.MULTILINE) is None:
        raise SystemExit(f"{path} does not match expected pattern: {pattern}")

require_regex(repo_root / "Cargo.toml", rf'^version = "{re.escape(version)}"$')

lock_path = repo_root / "Cargo.lock"
if lock_path.exists():
    lock_text = lock_path.read_text(encoding="utf-8")
    for package in workspace_packages:
        pattern = rf'\[\[package\]\]\nname = "{re.escape(package)}"\nversion = "{re.escape(version)}"'
        if re.search(pattern, lock_text) is None:
            raise SystemExit(f"Cargo.lock package {package} does not use version {version}")

project_path = repo_root / "apps/windows/ClipPlus.Windows/ClipPlus.Windows.csproj"
require_contains(project_path, f"<Version>{version}</Version>")
require_contains(project_path, f"<AssemblyVersion>{assembly_version}</AssemblyVersion>")
require_contains(project_path, f"<FileVersion>{assembly_version}</FileVersion>")
require_contains(project_path, f"<InformationalVersion>{version}</InformationalVersion>")

require_contains(
    repo_root / "apps/mac/Sources/ClipPlusMac/CoreBridge/CoreBridge.swift",
    f'core_version":"{version}"',
)
require_contains(
    repo_root / "apps/windows/ClipPlus.Windows/CoreBridge/CoreBridge.cs",
    f'core_version\\":\\"{version}\\"',
)
PY

echo "Release version verified: v$version"
