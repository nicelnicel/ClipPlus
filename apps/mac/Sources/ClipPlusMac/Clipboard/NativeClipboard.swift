import AppKit

struct NativeClipboard {
    func readFileURLs() -> [URL] {
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]

        return urls ?? []
    }

    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func writeFileURLs(_ urls: [URL]) -> Bool {
        guard Thread.isMainThread else {
            return false
        }

        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            return false
        }

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects(fileURLs as [NSURL])
    }

    func readPngImageData() -> Data? {
        if let pngData = NSPasteboard.general.data(forType: .png) {
            return pngData
        }

        guard let tiffData = NSPasteboard.general.data(forType: .tiff),
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return imageRep.representation(using: .png, properties: [:])
    }

    func writePngImageData(_ pngData: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(pngData, forType: .png)
    }
}
