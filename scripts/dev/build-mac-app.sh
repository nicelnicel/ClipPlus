#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mac_dir="$repo_root/apps/mac"
ffi_library="$repo_root/target/debug/libclipplus_ffi.dylib"
mac_output_dir="$mac_dir/.build/debug"

cd "$repo_root"
cargo build -p clipplus-ffi

cd "$mac_dir"
swift build

cp "$ffi_library" "$mac_output_dir/libclipplus_ffi.dylib"
CLIPPLUS_COREBRIDGE_SMOKE_TEST=1 "$mac_output_dir/ClipPlusMac"
