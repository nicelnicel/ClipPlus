import Foundation

struct MacUpdateInstaller {
    static func currentAppBundleURL(processURL: URL = Bundle.main.bundleURL) throws -> URL {
        guard processURL.pathExtension == "app" else {
            throw UpdateError.unsupportedRuntime
        }
        return processURL
    }

    static func makeInstallScript(
        dmgURL: URL,
        appBundleURL: URL,
        currentPID: Int32
    ) -> String {
        let dmgPath = shellQuoted(dmgURL.path)
        let appPath = shellQuoted(appBundleURL.path)
        let sharedKeyPath = shellQuoted(appBundleURL.appendingPathComponent("Contents/MacOS/clipplus.shared-key").path)
        let backupKeyPath = shellQuoted(FileManager.default.temporaryDirectory
            .appendingPathComponent("clipplus.shared-key.\(UUID().uuidString)").path)

        return """
        #!/bin/bash
        set -euo pipefail

        while kill -0 \(currentPID) >/dev/null 2>&1; do
          sleep 0.2
        done

        dmg_path=\(dmgPath)
        app_path=\(appPath)
        shared_key_path=\(sharedKeyPath)
        backup_key_path=\(backupKeyPath)
        mount_point="$(mktemp -d /tmp/clipplus-update.XXXXXX)"

        cleanup() {
          hdiutil detach "$mount_point" >/dev/null 2>&1 || true
          rm -rf "$mount_point"
          rm -f "$backup_key_path"
        }
        trap cleanup EXIT

        if [[ -f "$shared_key_path" ]]; then
          cp "$shared_key_path" "$backup_key_path"
        fi

        hdiutil attach "$dmg_path" -mountpoint "$mount_point" -nobrowse -quiet
        new_app="$mount_point/ClipPlus.app"
        if [[ ! -d "$new_app" ]]; then
          echo "ClipPlus.app not found in dmg" >&2
          exit 1
        fi

        rm -rf "$app_path"
        ditto "$new_app" "$app_path"
        if [[ -f "$backup_key_path" ]]; then
          cp "$backup_key_path" "$app_path/Contents/MacOS/clipplus.shared-key"
        fi

        open "\(appBundleURL.path)"
        """
    }

    func installAndRelaunch(downloadedUpdate: DownloadedUpdate) throws -> Never {
        let appBundleURL = try Self.currentAppBundleURL()
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipplus-mac-update-\(UUID().uuidString).sh")
        try Self.makeInstallScript(
            dmgURL: downloadedUpdate.fileURL,
            appBundleURL: appBundleURL,
            currentPID: getpid()
        ).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
        exit(0)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
