namespace ClipPlus.Windows.Clipboard;

using System.IO;
using System.Windows.Media.Imaging;

public sealed class NativeClipboard
{
    public IReadOnlyList<string> ReadFilePaths()
    {
        if (!System.Windows.Clipboard.ContainsFileDropList())
        {
            return Array.Empty<string>();
        }

        return System.Windows.Clipboard.GetFileDropList()
            .Cast<string>()
            .ToArray();
    }

    public string? ReadText()
    {
        return System.Windows.Clipboard.ContainsText()
            ? System.Windows.Clipboard.GetText()
            : null;
    }

    public void WriteText(string text)
    {
        System.Windows.Clipboard.SetText(text);
    }

    public byte[]? ReadPngImageData()
    {
        if (!System.Windows.Clipboard.ContainsImage())
        {
            return null;
        }

        var image = System.Windows.Clipboard.GetImage();
        if (image is null)
        {
            return null;
        }

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    public void WritePngImageData(byte[] pngData)
    {
        using var stream = new MemoryStream(pngData);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = stream;
        bitmap.EndInit();
        bitmap.Freeze();
        System.Windows.Clipboard.SetImage(bitmap);
    }
}
