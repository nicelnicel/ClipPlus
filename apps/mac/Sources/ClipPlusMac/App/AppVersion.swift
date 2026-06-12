import Foundation

enum AppVersion {
    static var current: String {
        if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !shortVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortVersion
        }

        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bundleVersion
        }

        return "dev"
    }

    static var display: String {
        "v\(current)"
    }

    static var settingsWindowTitle: String {
        "ClipPlus \(display) 设置"
    }
}
