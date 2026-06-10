#!/usr/bin/env bash
set -euo pipefail

cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build -p clipplus-ffi

if command -v swift >/dev/null 2>&1 && [ -f apps/mac/Package.swift ]; then
  (cd apps/mac && CLIPPLUS_FFI_LIBRARY_PATH="$PWD/../../target/debug/libclipplus_ffi.dylib" swift test)
fi

if command -v dotnet >/dev/null 2>&1 && [ -f apps/windows/ClipPlus.Windows.sln ]; then
  (cd apps/windows && dotnet test)
fi
