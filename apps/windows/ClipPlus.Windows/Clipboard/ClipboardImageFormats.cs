namespace ClipPlus.Windows.Clipboard;

using System.Buffers.Binary;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;

public static class ClipboardImageFormats
{
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

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern UIntPtr GlobalSize(IntPtr hMem);

        internal static byte[]? ReadBytes(uint format)
        {
            if (format == 0)
            {
                return null;
            }

            var opened = false;
            for (var attempt = 0; attempt < 3; attempt++)
            {
                if (OpenClipboard(IntPtr.Zero))
                {
                    opened = true;
                    break;
                }

                Thread.Sleep(10);
            }

            if (!opened)
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
    }
}
