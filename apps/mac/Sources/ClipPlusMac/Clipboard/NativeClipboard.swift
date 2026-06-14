import AppKit

struct NativeClipboard {
    private static let applePngPasteboardType = NSPasteboard.PasteboardType("Apple PNG pasteboard type")
    private static let nextTiffPasteboardType = NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")

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
            writeImageRepresentations(pngData, to: NSPasteboard.general)
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
        writeImageRepresentations(pngData, to: NSPasteboard.general)
    }

    private func writeImageRepresentations(_ pngData: Data, to pasteboard: NSPasteboard) {
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(pngData, forType: Self.applePngPasteboardType)

        guard let tiffData = tiffData(fromPNGData: pngData) else {
            return
        }

        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.setData(tiffData, forType: Self.nextTiffPasteboardType)
    }

    private func tiffData(fromPNGData pngData: Data) -> Data? {
        if let image = NSImage(data: pngData),
           let tiffData = image.tiffRepresentation {
            return tiffData
        }

        return NSBitmapImageRep(data: pngData)?.representation(using: .tiff, properties: [:])
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
