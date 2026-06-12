#!/usr/bin/env bash
set -euo pipefail

install_app=0
open_app=0

for arg in "$@"; do
    case "$arg" in
        --install)
            install_app=1
            ;;
        --open)
            open_app=1
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--install] [--open]" >&2
            exit 2
            ;;
    esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mac_dir="$repo_root/apps/mac"
version_file="$repo_root/VERSION"
app_dir="$repo_root/target/macos-build.noindex/ClipPlus.app"
legacy_indexed_app="$repo_root/target/macos/ClipPlus.app"
installed_app="/Applications/ClipPlus.app"
legacy_tmp_app="/private/tmp/ClipPlusMac.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
frameworks_dir="$contents_dir/Frameworks"
resources_dir="$contents_dir/Resources"
plist_path="$contents_dir/Info.plist"
shared_key_name="clipplus.shared-key"
preserved_shared_key=""
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
    if [[ -n "$preserved_shared_key" ]]; then
        rm -f "$preserved_shared_key"
    fi
}
trap cleanup EXIT

unregister_app() {
    local candidate="$1"
    if [[ -x "$lsregister" ]]; then
        "$lsregister" -u "$candidate" >/dev/null 2>&1 || true
    fi
}

if [[ ! -f "$version_file" ]]; then
    echo "Missing VERSION file: $version_file" >&2
    exit 1
fi

app_version="$(tr -d '[:space:]' < "$version_file")"
if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be MAJOR.MINOR.PATCH, got: $app_version" >&2
    exit 1
fi

cd "$repo_root"
cargo build --release -p clipplus-ffi

cd "$mac_dir"
swift build -c release

cd "$repo_root"
unregister_app "$legacy_indexed_app"
rm -rf "$app_dir" "$legacy_indexed_app"
mkdir -p "$macos_dir" "$frameworks_dir" "$resources_dir"

cp "$mac_dir/.build/release/ClipPlusMac" "$macos_dir/ClipPlusMac"
cp "$repo_root/target/release/libclipplus_ffi.dylib" "$frameworks_dir/libclipplus_ffi.dylib"
cp "$mac_dir/Resources/ClipPlus.icns" "$resources_dir/ClipPlus.icns"
cp "$mac_dir/Resources/ClipPlusMenuBar.png" "$resources_dir/ClipPlusMenuBar.png"
chmod +x "$macos_dir/ClipPlusMac"

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>ClipPlusMac</string>
    <key>CFBundleIconFile</key>
    <string>ClipPlus.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.clipplus.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ClipPlus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${app_version}</string>
    <key>CFBundleVersion</key>
    <string>${app_version}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>ClipPlus 需要访问局域网以同步剪贴板。</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$app_dir" >/dev/null
    codesign --verify --deep --strict "$app_dir"
fi

if [[ "$install_app" -eq 1 ]]; then
    if [[ -f "$installed_app/Contents/MacOS/$shared_key_name" ]]; then
        preserved_shared_key="$(mktemp "${TMPDIR:-/tmp}/clipplus-shared-key.XXXXXX")"
        cp "$installed_app/Contents/MacOS/$shared_key_name" "$preserved_shared_key"
    fi
    unregister_app "$legacy_tmp_app"
    unregister_app "$legacy_indexed_app"
    unregister_app "$app_dir"
    unregister_app "$installed_app"
    rm -rf "$installed_app"
    cp -R "$app_dir" "$installed_app"
    if [[ -n "$preserved_shared_key" && -f "$preserved_shared_key" ]]; then
        cp "$preserved_shared_key" "$installed_app/Contents/MacOS/$shared_key_name"
    fi
    rm -rf "$legacy_tmp_app" "$legacy_indexed_app" "$app_dir"
    app_dir="$installed_app"
    mdimport "$app_dir" >/dev/null 2>&1 || true
fi

echo "ClipPlus macOS app: $app_dir"
echo "Run with: open \"$app_dir\""

if [[ "$open_app" -eq 1 ]]; then
    open "$app_dir"
fi
