#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 MAJOR.MINOR.PATCH" >&2
    exit 2
fi

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be MAJOR.MINOR.PATCH, got: $version" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

def replace_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    next_text, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected one replacement in {path}")
    path.write_text(next_text, encoding="utf-8")

(repo_root / "VERSION").write_text(f"{version}\n", encoding="utf-8")

replace_once(
    repo_root / "Cargo.toml",
    r'(?m)^version = "[0-9]+\.[0-9]+\.[0-9]+"$',
    f'version = "{version}"',
)

lock_path = repo_root / "Cargo.lock"
if lock_path.exists():
    lock_text = lock_path.read_text(encoding="utf-8")
    package_blocks = lock_text.split("[[package]]")
    next_blocks = [package_blocks[0]]
    changed_packages = set()
    for block in package_blocks[1:]:
        name_match = re.search(r'(?m)^name = "([^"]+)"$', block)
        if name_match and name_match.group(1) in workspace_packages:
            block, count = re.subn(
                r'(?m)^version = "[0-9]+\.[0-9]+\.[0-9]+"$',
                f'version = "{version}"',
                block,
                count=1,
            )
            if count != 1:
                raise SystemExit(f"Expected one Cargo.lock version replacement for {name_match.group(1)}")
            changed_packages.add(name_match.group(1))
        next_blocks.append("[[package]]" + block)
    missing = workspace_packages - changed_packages
    if missing:
        raise SystemExit(f"Missing Cargo.lock workspace packages: {', '.join(sorted(missing))}")
    lock_path.write_text("".join(next_blocks), encoding="utf-8")

project_path = repo_root / "apps/windows/ClipPlus.Windows/ClipPlus.Windows.csproj"
replace_once(project_path, r"(?m)^    <Version>[^<]+</Version>$", f"    <Version>{version}</Version>")
replace_once(
    project_path,
    r"(?m)^    <AssemblyVersion>[^<]+</AssemblyVersion>$",
    f"    <AssemblyVersion>{assembly_version}</AssemblyVersion>",
)
replace_once(project_path, r"(?m)^    <FileVersion>[^<]+</FileVersion>$", f"    <FileVersion>{assembly_version}</FileVersion>")
replace_once(
    project_path,
    r"(?m)^    <InformationalVersion>[^<]+</InformationalVersion>$",
    f"    <InformationalVersion>{version}</InformationalVersion>",
)

replace_once(
    repo_root / "apps/mac/Sources/ClipPlusMac/CoreBridge/CoreBridge.swift",
    r'core_version":"[0-9]+\.[0-9]+\.[0-9]+"',
    f'core_version":"{version}"',
)
replace_once(
    repo_root / "apps/windows/ClipPlus.Windows/CoreBridge/CoreBridge.cs",
    r'core_version\\":\\"[0-9]+\.[0-9]+\.[0-9]+\\"',
    f'core_version\\":\\"{version}\\"',
)
PY

"$repo_root/scripts/dev/check-release-version.sh" "v$version"

echo "ClipPlus version updated to $version"
