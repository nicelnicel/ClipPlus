namespace ClipPlus.Windows.Clipboard;

using System.Buffers.Binary;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Media.Imaging;

public static class ClipboardImageFormats
{
    private const uint CfBitmap = 2;
    private const uint CfDib = 8;
    private const uint CfDibV5 = 17;
    private const uint BiBitFields = 3;
    private const uint BiAlphaBitFields = 6;

    private static readonly byte[] PngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    public static bool IsPng(byte[] data)
    {
        return data.Length >= PngSignature.Length
            && data.AsSpan(0, PngSignature.Length).SequenceEqual(PngSignature);
    }

    public static string AvailableClipboardFormatsSummary()
    {
        var names = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            var dataObject = System.Windows.Clipboard.GetDataObject();
            if (dataObject is not null)
            {
                foreach (var format in dataObject.GetFormats(autoConvert: false))
                {
                    AddFormatName(names, format);
                }
            }
        }
        catch (Exception)
        {
            // Clipboard owners may deny or delay format rendering; native enumeration below is best effort.
        }

        foreach (var formatName in NativeClipboardFormats.EnumerateFormatNames())
        {
            AddFormatName(names, formatName);
        }

        return string.Join(", ", names.Take(32));
    }

    public static byte[]? ConvertDibToPng(byte[] dibData)
    {
        if (dibData.Length < 12)
        {
            return null;
        }

        try
        {
            var headerSize = BinaryPrimitives.ReadUInt32LittleEndian(dibData.AsSpan(0, 4));
            if (headerSize < 12 || headerSize > dibData.Length || headerSize > int.MaxValue)
            {
                return null;
            }

            var dibPixelOffset = CalculateDibPixelOffset(dibData, (int)headerSize);
            if (dibPixelOffset < 0 || dibPixelOffset > dibData.Length)
            {
                return null;
            }

            var bmpData = new byte[14 + dibData.Length];
            bmpData[0] = 0x42;
            bmpData[1] = 0x4D;
            BinaryPrimitives.WriteUInt32LittleEndian(bmpData.AsSpan(2, 4), (uint)bmpData.Length);
            BinaryPrimitives.WriteUInt32LittleEndian(bmpData.AsSpan(10, 4), (uint)(14 + dibPixelOffset));
            dibData.CopyTo(bmpData.AsSpan(14));

            using var stream = new MemoryStream(bmpData);
            var decoder = BitmapDecoder.Create(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad
            );
            return decoder.Frames.Count == 0
                ? null
                : EncodeBitmapSourceToPng(decoder.Frames[0]);
        }
        catch (Exception)
        {
            return null;
        }
    }

    internal static byte[]? ReadPngFromDataObject(System.Windows.IDataObject? dataObject)
    {
        if (dataObject is null)
        {
            return null;
        }

        foreach (var format in new[] { "PNG", "image/png" })
        {
            try
            {
                if (!dataObject.GetDataPresent(format, autoConvert: false))
                {
                    continue;
                }

                var pngData = PngBytesFromPayload(dataObject.GetData(format, autoConvert: false));
                if (pngData is not null)
                {
                    return pngData;
                }
            }
            catch (Exception)
            {
                continue;
            }
        }

        return null;
    }

    internal static byte[]? ReadNativePngFormat(string formatName)
    {
        var format = NativeClipboardFormats.RegisterClipboardFormat(formatName);
        if (format == 0)
        {
            return null;
        }

        return PngBytesFromPayload(NativeClipboardFormats.ReadBytes(format));
    }

    internal static byte[]? ReadNativeDib()
    {
        foreach (var format in new[] { CfDibV5, CfDib })
        {
            var dibData = NativeClipboardFormats.ReadBytes(format);
            if (dibData is null)
            {
                continue;
            }

            var pngData = ConvertDibToPng(dibData);
            if (pngData is not null)
            {
                return pngData;
            }
        }

        return null;
    }

    internal static byte[]? ReadNativeBitmap()
    {
        var handle = NativeClipboardFormats.ReadHandle(CfBitmap);
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            using var image = System.Drawing.Image.FromHbitmap(handle);
            using var stream = new MemoryStream();
            image.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
            return stream.ToArray();
        }
        catch (Exception)
        {
            return null;
        }
    }

    internal static byte[]? EncodeBitmapSourceToPng(BitmapSource image)
    {
        try
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = new MemoryStream();
            encoder.Save(stream);
            return stream.ToArray();
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static byte[]? PngBytesFromPayload(object? payload)
    {
        switch (payload)
        {
            case null:
                return null;
            case byte[] bytes:
                return IsPng(bytes) ? bytes : null;
            case MemoryStream memoryStream:
            {
                var bytes = memoryStream.ToArray();
                return IsPng(bytes) ? bytes : null;
            }
            case Stream stream:
            {
                using var copy = new MemoryStream();
                var originalPosition = stream.CanSeek ? stream.Position : 0;
                if (stream.CanSeek)
                {
                    stream.Position = 0;
                }

                stream.CopyTo(copy);
                if (stream.CanSeek)
                {
                    stream.Position = originalPosition;
                }

                var bytes = copy.ToArray();
                return IsPng(bytes) ? bytes : null;
            }
            default:
                return null;
        }
    }

    private static int CalculateDibPixelOffset(byte[] dibData, int headerSize)
    {
        if (headerSize == 12)
        {
            if (dibData.Length < 12)
            {
                return -1;
            }

            var bitCount = BinaryPrimitives.ReadUInt16LittleEndian(dibData.AsSpan(10, 2));
            var paletteBytes = bitCount <= 8 ? (1 << bitCount) * 3 : 0;
            return headerSize + paletteBytes;
        }

        if (headerSize < 40 || dibData.Length < 40)
        {
            return -1;
        }

        var bitCountModern = BinaryPrimitives.ReadUInt16LittleEndian(dibData.AsSpan(14, 2));
        var compression = BinaryPrimitives.ReadUInt32LittleEndian(dibData.AsSpan(16, 4));
        var colorCount = BinaryPrimitives.ReadUInt32LittleEndian(dibData.AsSpan(32, 4));
        var paletteEntryCount = colorCount != 0
            ? colorCount
            : bitCountModern <= 8 ? 1u << bitCountModern : 0u;
        if (paletteEntryCount > int.MaxValue / 4)
        {
            return -1;
        }

        var maskBytes = headerSize == 40 && compression is BiBitFields or BiAlphaBitFields
            ? compression == BiAlphaBitFields ? 16 : 12
            : 0;

        return checked(headerSize + maskBytes + ((int)paletteEntryCount * 4));
    }

    private static void AddFormatName(ISet<string> names, string? formatName)
    {
        if (string.IsNullOrWhiteSpace(formatName))
        {
            return;
        }

        var sanitized = formatName
            .Replace('\r', ' ')
            .Replace('\n', ' ')
            .Replace('\t', ' ')
            .Trim();
        if (sanitized.Length == 0)
        {
            return;
        }

        if (sanitized.Length > 80)
        {
            sanitized = sanitized[..77] + "...";
        }

        names.Add(sanitized);
    }

    private static class NativeClipboardFormats
    {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern uint RegisterClipboardFormat(string lpszFormat);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool IsClipboardFormatAvailable(uint format);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetClipboardData(uint uFormat);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint EnumClipboardFormats(uint format);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetClipboardFormatName(uint format, StringBuilder lpszFormatName, int cchMaxCount);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern UIntPtr GlobalSize(IntPtr hMem);

        internal static IReadOnlyList<string> EnumerateFormatNames()
        {
            if (!TryOpenClipboard())
            {
                return Array.Empty<string>();
            }

            try
            {
                var names = new List<string>();
                var format = 0u;
                while (names.Count < 64)
                {
                    format = EnumClipboardFormats(format);
                    if (format == 0)
                    {
                        break;
                    }

                    names.Add(FormatName(format));
                }

                return names;
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        internal static IntPtr ReadHandle(uint format)
        {
            if (format == 0 || !TryOpenClipboard())
            {
                return IntPtr.Zero;
            }

            try
            {
                if (!IsClipboardFormatAvailable(format))
                {
                    return IntPtr.Zero;
                }

                return GetClipboardData(format);
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        internal static byte[]? ReadBytes(uint format)
        {
            if (format == 0)
            {
                return null;
            }

            if (!TryOpenClipboard())
            {
                return null;
            }

            try
            {
                if (!IsClipboardFormatAvailable(format))
                {
                    return null;
                }

                var handle = GetClipboardData(format);
                if (handle == IntPtr.Zero)
                {
                    return null;
                }

                var size = GlobalSize(handle).ToUInt64();
                if (size == 0 || size > int.MaxValue)
                {
                    return null;
                }

                var pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero)
                {
                    return null;
                }

                try
                {
                    var bytes = new byte[(int)size];
                    Marshal.Copy(pointer, bytes, 0, bytes.Length);
                    return bytes;
                }
                finally
                {
                    _ = GlobalUnlock(handle);
                }
            }
            finally
            {
                _ = CloseClipboard();
            }
        }

        private static bool TryOpenClipboard()
        {
            for (var attempt = 0; attempt < 3; attempt++)
            {
                if (OpenClipboard(IntPtr.Zero))
                {
                    return true;
                }

                Thread.Sleep(10);
            }

            return false;
        }

        private static string FormatName(uint format)
        {
            var standardName = StandardFormatName(format);
            if (standardName is not null)
            {
                return standardName;
            }

            var builder = new StringBuilder(128);
            if (GetClipboardFormatName(format, builder, builder.Capacity) > 0)
            {
                return builder.ToString();
            }

            return $"FORMAT_{format}";
        }

        private static string? StandardFormatName(uint format)
        {
            return format switch
            {
                1 => "CF_TEXT",
                2 => "CF_BITMAP",
                3 => "CF_METAFILEPICT",
                4 => "CF_SYLK",
                5 => "CF_DIF",
                6 => "CF_TIFF",
                7 => "CF_OEMTEXT",
                8 => "CF_DIB",
                13 => "CF_UNICODETEXT",
                14 => "CF_ENHMETAFILE",
                15 => "CF_HDROP",
                16 => "CF_LOCALE",
                17 => "CF_DIBV5",
                _ => null
            };
        }
    }
}
