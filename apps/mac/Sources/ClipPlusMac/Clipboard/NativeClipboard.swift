import AppKit

struct NativeClipboard {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
