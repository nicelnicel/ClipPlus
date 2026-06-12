namespace ClipPlus.Windows.Clipboard;

using System.Collections.Specialized;
using System.IO;
using System.Threading;
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

    public bool WriteFilePaths(IReadOnlyList<string> paths)
    {
        // WPF Clipboard requires an STA thread; callers should use the UI Dispatcher.
        if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA || paths.Count == 0)
        {
            return false;
        }

        try
        {
            var collection = new StringCollection();
            var validPaths = new List<string>();
            foreach (var path in paths.Where(path => !string.IsNullOrWhiteSpace(path)))
            {
                collection.Add(path);
                validPaths.Add(path);
            }

            if (collection.Count == 0)
            {
                return false;
            }

            var dataObject = new System.Windows.DataObject();
            dataObject.SetFileDropList(collection);
            var image = LoadImageForSingleImageFile(validPaths);
            if (image is not null)
            {
                dataObject.SetImage(image);
            }

            System.Windows.Clipboard.SetDataObject(dataObject, true);
            return true;
        }
        catch (Exception)
        {
            return false;
        }
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

    private static BitmapSource? LoadImageForSingleImageFile(IReadOnlyList<string> paths)
    {
        if (paths.Count != 1)
        {
            return null;
        }

        var path = paths[0];
        if (!IsSupportedImageFile(path) || !File.Exists(path))
        {
            return null;
        }

        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.UriSource = new Uri(path, UriKind.Absolute);
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    private static bool IsSupportedImageFile(string path)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        return extension is ".png"
            or ".jpg"
            or ".jpeg"
            or ".gif"
            or ".bmp"
            or ".tif"
            or ".tiff"
            or ".webp";
    }
}
