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

        let pngData = pngImageDataForSingleImageFile(fileURLs)
        NSPasteboard.general.clearContents()
        let wroteFiles = NSPasteboard.general.writeObjects(fileURLs as [NSURL])
        if let pngData {
            NSPasteboard.general.setData(pngData, forType: .png)
        }
        return wroteFiles
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

    private func pngImageDataForSingleImageFile(_ urls: [URL]) -> Data? {
        guard urls.count == 1 else {
            return nil
        }

        let url = urls[0]
        guard isSupportedImageFile(url) else {
            return nil
        }

        if url.pathExtension.lowercased() == "png",
           let data = try? Data(contentsOf: url),
           NSBitmapImageRep(data: data) != nil {
            return data
        }

        guard let image = NSImage(contentsOf: url),
              let tiffData = image.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return imageRep.representation(using: .png, properties: [:])
    }

    private func isSupportedImageFile(_ url: URL) -> Bool {
        let supportedExtensions: Set<String> = [
            "png",
            "jpg",
            "jpeg",
            "gif",
            "bmp",
            "tif",
            "tiff",
            "webp",
            "heic",
            "heif"
        ]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
