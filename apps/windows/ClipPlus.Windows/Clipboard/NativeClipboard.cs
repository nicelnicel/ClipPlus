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
                SetPngFormats(dataObject, ClipboardImageFormats.EncodeBitmapSourceToPng(image));
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
        return ReadClipboardDataObjectPng()
            ?? ClipboardImageFormats.ReadNativePngFormat("PNG")
            ?? ClipboardImageFormats.ReadNativePngFormat("image/png")
            ?? ReadWpfImageAsPng()
            ?? ClipboardImageFormats.ReadNativeDib()
            ?? ClipboardImageFormats.ReadNativeBitmap()
            ?? ReadWinFormsImageAsPng();
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

        var dataObject = new System.Windows.DataObject();
        dataObject.SetImage(bitmap);
        SetPngFormats(dataObject, pngData);
        System.Windows.Clipboard.SetDataObject(dataObject, true);
    }

    private static void SetPngFormats(System.Windows.DataObject dataObject, byte[]? pngData)
    {
        if (pngData is null)
        {
            return;
        }

        dataObject.SetData("PNG", new MemoryStream(pngData));
        dataObject.SetData("image/png", new MemoryStream(pngData));
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

    private static byte[]? ReadWpfImageAsPng()
    {
        try
        {
            if (!System.Windows.Clipboard.ContainsImage())
            {
                return null;
            }

            var image = System.Windows.Clipboard.GetImage();
            return image is null ? null : ClipboardImageFormats.EncodeBitmapSourceToPng(image);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static byte[]? ReadClipboardDataObjectPng()
    {
        try
        {
            return ClipboardImageFormats.ReadPngFromDataObject(System.Windows.Clipboard.GetDataObject());
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static byte[]? ReadWinFormsImageAsPng()
    {
        try
        {
            using var image = System.Windows.Forms.Clipboard.GetImage();
            if (image is null)
            {
                return null;
            }

            using var stream = new MemoryStream();
            image.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
            return stream.ToArray();
        }
        catch (Exception)
        {
            return null;
        }
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
