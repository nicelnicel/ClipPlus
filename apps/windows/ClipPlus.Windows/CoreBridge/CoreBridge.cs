namespace ClipPlus.Windows.CoreBridge;

using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

public sealed class CoreBridge
{
    public string StatusJson()
    {
        return "{\"core_version\":\"0.1.0\"}";
    }

    public string? DeriveGroupId(string rawKey)
    {
        return Ffi.Value?.DeriveGroupId(rawKey);
    }

    public string? CreateHelloMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName)
    {
        return Ffi.Value?.CreateHelloMessageJson(groupId, senderDeviceId, senderDeviceName);
    }

    public string? CreateTextMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string text)
    {
        return Ffi.Value?.CreateTextMessageJson(groupId, senderDeviceId, senderDeviceName, text);
    }

    public string? CreateImageMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        byte[] pngData)
    {
        return Ffi.Value?.CreateImageMessageJson(groupId, senderDeviceId, senderDeviceName, pngData);
    }

    public string? CreateFileOfferMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string transferId,
        IReadOnlyList<ClipPlus.Windows.Sync.FileTransferItem> files,
        int archivePort)
    {
        return Ffi.Value?.CreateFileOfferMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName,
            transferId,
            files,
            archivePort);
    }

    public bool WriteFileArchiveZip(IReadOnlyList<string> sourcePaths, string archivePath)
    {
        return Ffi.Value?.WriteFileArchiveZip(sourcePaths, archivePath) == true;
    }

    public string? CreateTrustMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string approvedDeviceId)
    {
        return Ffi.Value?.CreateTrustMessageJson(groupId, senderDeviceId, senderDeviceName, approvedDeviceId);
    }

    private static readonly Lazy<ClipPlusFfiBridge?> Ffi = new(ClipPlusFfiBridge.Load);
}

internal sealed class ClipPlusFfiBridge
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr DeriveGroupIdDelegate(IntPtr rawKey);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateHelloMessageJsonDelegate(
        IntPtr groupId,
        IntPtr senderDeviceId,
        IntPtr senderDeviceName);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateTextMessageJsonDelegate(
        IntPtr groupId,
        IntPtr senderDeviceId,
        IntPtr senderDeviceName,
        IntPtr text);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateImageMessageJsonDelegate(
        IntPtr groupId,
        IntPtr senderDeviceId,
        IntPtr senderDeviceName,
        IntPtr imageBytes,
        UIntPtr imageLen);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateFileOfferMessageJsonDelegate(
        IntPtr groupId,
        IntPtr senderDeviceId,
        IntPtr senderDeviceName,
        IntPtr transferId,
        IntPtr filesJson,
        ushort archivePort);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool WriteFileArchiveZipDelegate(
        IntPtr sourcePathsJson,
        IntPtr archivePath);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void FreeStringDelegate(IntPtr value);

    private static readonly JsonSerializerOptions FilesJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly DeriveGroupIdDelegate deriveGroupId;
    private readonly CreateHelloMessageJsonDelegate createHelloMessageJson;
    private readonly CreateTextMessageJsonDelegate createTextMessageJson;
    private readonly CreateImageMessageJsonDelegate createImageMessageJson;
    private readonly CreateFileOfferMessageJsonDelegate createFileOfferMessageJson;
    private readonly WriteFileArchiveZipDelegate writeFileArchiveZip;
    private readonly CreateTextMessageJsonDelegate createTrustMessageJson;
    private readonly FreeStringDelegate freeString;

    private ClipPlusFfiBridge(
        DeriveGroupIdDelegate deriveGroupId,
        CreateHelloMessageJsonDelegate createHelloMessageJson,
        CreateTextMessageJsonDelegate createTextMessageJson,
        CreateImageMessageJsonDelegate createImageMessageJson,
        CreateFileOfferMessageJsonDelegate createFileOfferMessageJson,
        WriteFileArchiveZipDelegate writeFileArchiveZip,
        CreateTextMessageJsonDelegate createTrustMessageJson,
        FreeStringDelegate freeString)
    {
        this.deriveGroupId = deriveGroupId;
        this.createHelloMessageJson = createHelloMessageJson;
        this.createTextMessageJson = createTextMessageJson;
        this.createImageMessageJson = createImageMessageJson;
        this.createFileOfferMessageJson = createFileOfferMessageJson;
        this.writeFileArchiveZip = writeFileArchiveZip;
        this.createTrustMessageJson = createTrustMessageJson;
        this.freeString = freeString;
    }

    public static ClipPlusFfiBridge? Load()
    {
        foreach (var candidatePath in LibraryCandidatePaths())
        {
            if (!File.Exists(candidatePath))
            {
                continue;
            }

            if (!NativeLibrary.TryLoad(candidatePath, out var handle))
            {
                continue;
            }

            if (!NativeLibrary.TryGetExport(handle, "clipplus_derive_group_id", out var deriveSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_hello_message_json", out var createHelloMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_text_message_json", out var createTextMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_image_message_json", out var createImageMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_file_offer_message_json", out var createFileOfferMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_write_file_archive_zip", out var writeFileArchiveZipSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_trust_message_json", out var createTrustMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_free_string", out var freeSymbol))
            {
                NativeLibrary.Free(handle);
                continue;
            }

            return new ClipPlusFfiBridge(
                Marshal.GetDelegateForFunctionPointer<DeriveGroupIdDelegate>(deriveSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateHelloMessageJsonDelegate>(createHelloMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateTextMessageJsonDelegate>(createTextMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateImageMessageJsonDelegate>(createImageMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateFileOfferMessageJsonDelegate>(createFileOfferMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<WriteFileArchiveZipDelegate>(writeFileArchiveZipSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateTextMessageJsonDelegate>(createTrustMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<FreeStringDelegate>(freeSymbol)
            );
        }

        return null;
    }

    public string? DeriveGroupId(string rawKey)
    {
        var rawKeyPointer = Marshal.StringToCoTaskMemUTF8(rawKey);
        try
        {
            var resultPointer = deriveGroupId(rawKeyPointer);
            if (resultPointer == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                return Marshal.PtrToStringUTF8(resultPointer);
            }
            finally
            {
                freeString(resultPointer);
            }
        }
        finally
        {
            Marshal.FreeCoTaskMem(rawKeyPointer);
        }
    }

    public string? CreateTextMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string text)
    {
        return CreateFourStringMessageJson(createTextMessageJson, groupId, senderDeviceId, senderDeviceName, text);
    }

    public string? CreateHelloMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName)
    {
        var groupIdPointer = Marshal.StringToCoTaskMemUTF8(groupId);
        var senderDeviceIdPointer = Marshal.StringToCoTaskMemUTF8(senderDeviceId);
        var senderDeviceNamePointer = Marshal.StringToCoTaskMemUTF8(senderDeviceName);
        try
        {
            return TakeOwnedString(createHelloMessageJson(
                groupIdPointer,
                senderDeviceIdPointer,
                senderDeviceNamePointer));
        }
        finally
        {
            Marshal.FreeCoTaskMem(groupIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceNamePointer);
        }
    }

    public string? CreateImageMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        byte[] pngData)
    {
        if (pngData.Length == 0)
        {
            return null;
        }

        var groupIdPointer = Marshal.StringToCoTaskMemUTF8(groupId);
        var senderDeviceIdPointer = Marshal.StringToCoTaskMemUTF8(senderDeviceId);
        var senderDeviceNamePointer = Marshal.StringToCoTaskMemUTF8(senderDeviceName);
        var imageHandle = GCHandle.Alloc(pngData, GCHandleType.Pinned);
        try
        {
            return TakeOwnedString(createImageMessageJson(
                groupIdPointer,
                senderDeviceIdPointer,
                senderDeviceNamePointer,
                imageHandle.AddrOfPinnedObject(),
                new UIntPtr((ulong)pngData.LongLength)));
        }
        finally
        {
            imageHandle.Free();
            Marshal.FreeCoTaskMem(groupIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceNamePointer);
        }
    }

    public string? CreateFileOfferMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string transferId,
        IReadOnlyList<ClipPlus.Windows.Sync.FileTransferItem> files,
        int archivePort)
    {
        if (archivePort <= 0 || archivePort > ushort.MaxValue)
        {
            return null;
        }

        var filesJson = JsonSerializer.Serialize(files, FilesJsonOptions);
        var groupIdPointer = Marshal.StringToCoTaskMemUTF8(groupId);
        var senderDeviceIdPointer = Marshal.StringToCoTaskMemUTF8(senderDeviceId);
        var senderDeviceNamePointer = Marshal.StringToCoTaskMemUTF8(senderDeviceName);
        var transferIdPointer = Marshal.StringToCoTaskMemUTF8(transferId);
        var filesJsonPointer = Marshal.StringToCoTaskMemUTF8(filesJson);
        try
        {
            return TakeOwnedString(createFileOfferMessageJson(
                groupIdPointer,
                senderDeviceIdPointer,
                senderDeviceNamePointer,
                transferIdPointer,
                filesJsonPointer,
                (ushort)archivePort));
        }
        finally
        {
            Marshal.FreeCoTaskMem(groupIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceNamePointer);
            Marshal.FreeCoTaskMem(transferIdPointer);
            Marshal.FreeCoTaskMem(filesJsonPointer);
        }
    }

    public string? CreateTrustMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string approvedDeviceId)
    {
        return CreateFourStringMessageJson(createTrustMessageJson, groupId, senderDeviceId, senderDeviceName, approvedDeviceId);
    }

    public bool WriteFileArchiveZip(IReadOnlyList<string> sourcePaths, string archivePath)
    {
        var sourcePathsJson = JsonSerializer.Serialize(sourcePaths);
        var sourcePathsJsonPointer = Marshal.StringToCoTaskMemUTF8(sourcePathsJson);
        var archivePathPointer = Marshal.StringToCoTaskMemUTF8(archivePath);
        try
        {
            return writeFileArchiveZip(sourcePathsJsonPointer, archivePathPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(sourcePathsJsonPointer);
            Marshal.FreeCoTaskMem(archivePathPointer);
        }
    }

    private string? CreateFourStringMessageJson(
        CreateTextMessageJsonDelegate createMessageJson,
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string payload)
    {
        var groupIdPointer = Marshal.StringToCoTaskMemUTF8(groupId);
        var senderDeviceIdPointer = Marshal.StringToCoTaskMemUTF8(senderDeviceId);
        var senderDeviceNamePointer = Marshal.StringToCoTaskMemUTF8(senderDeviceName);
        var payloadPointer = Marshal.StringToCoTaskMemUTF8(payload);
        try
        {
            return TakeOwnedString(createMessageJson(
                groupIdPointer,
                senderDeviceIdPointer,
                senderDeviceNamePointer,
                payloadPointer));
        }
        finally
        {
            Marshal.FreeCoTaskMem(groupIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceNamePointer);
            Marshal.FreeCoTaskMem(payloadPointer);
        }
    }

    private string? TakeOwnedString(IntPtr resultPointer)
    {
        if (resultPointer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return Marshal.PtrToStringUTF8(resultPointer);
        }
        finally
        {
            freeString(resultPointer);
        }
    }

    private static IEnumerable<string> LibraryCandidatePaths()
    {
        var environmentPath = Environment.GetEnvironmentVariable("CLIPPLUS_FFI_LIBRARY_PATH");
        if (!string.IsNullOrWhiteSpace(environmentPath))
        {
            yield return environmentPath;
        }

        yield return Path.Combine(AppContext.BaseDirectory, "clipplus_ffi.dll");
    }
}
