namespace ClipPlus.Windows.CoreBridge;

using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

public sealed class CoreBridge
{
    public string StatusJson()
    {
        return "{\"core_version\":\"0.1.15\"}";
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

    public string? CreateImageOfferMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string transferId,
        byte[] pngData,
        int archivePort)
    {
        return Ffi.Value?.CreateImageOfferMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName,
            transferId,
            pngData,
            archivePort);
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

    public ulong ServeFileArchiveToSocket(IntPtr socket, IReadOnlyList<string> sourcePaths, string archivePath)
    {
        return Ffi.Value?.ServeFileArchiveToSocket(socket, sourcePaths, archivePath) ?? 0;
    }

    public bool DownloadFileArchive(string host, int port, string transferId, string destinationPath)
    {
        return Ffi.Value?.DownloadFileArchive(host, port, transferId, destinationPath) == true;
    }

    public FileTreeDownloadResult? DownloadFileTree(string host, int port, string transferId, string destinationDirectory)
    {
        return Ffi.Value?.DownloadFileTree(host, port, transferId, destinationDirectory);
    }

    public RustUdpSocket? OpenUdpSocket(int bindPort)
    {
        return Ffi.Value?.OpenUdpSocket(bindPort);
    }

    public RustFileServer? OpenFileServer(int bindPort)
    {
        return Ffi.Value?.OpenFileServer(bindPort);
    }

    public string? CreateTrustMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string approvedDeviceId)
    {
        return Ffi.Value?.CreateTrustMessageJson(groupId, senderDeviceId, senderDeviceName, approvedDeviceId);
    }

    internal IReadOnlyList<string> FfiLoadDiagnostics()
    {
        return ClipPlusFfiBridge.LoadDiagnostics();
    }

    private static readonly Lazy<ClipPlusFfiBridge?> Ffi = new(ClipPlusFfiBridge.Load);
}

public sealed record RustUdpDatagram(byte[] Payload, string SourceHost, int SourcePort);

public sealed record FileTreeDownloadResult(int FileCount, ulong ByteCount, IReadOnlyList<string> TopLevelPaths);

public sealed class RustUdpSocket : IDisposable
{
    private readonly ClipPlusFfiBridge bridge;
    private IntPtr handle;

    internal RustUdpSocket(ClipPlusFfiBridge bridge, IntPtr handle)
    {
        this.bridge = bridge;
        this.handle = handle;
    }

    public int LocalPort => handle == IntPtr.Zero ? 0 : bridge.UdpSocketLocalPort(handle);

    public bool SendTo(byte[] payload, string targetHost, int targetPort)
    {
        return handle != IntPtr.Zero && bridge.UdpSocketSendTo(handle, payload, targetHost, targetPort);
    }

    public RustUdpDatagram? Receive()
    {
        return handle == IntPtr.Zero ? null : bridge.UdpSocketReceive(handle);
    }

    public void Dispose()
    {
        var currentHandle = System.Threading.Interlocked.Exchange(ref handle, IntPtr.Zero);
        if (currentHandle != IntPtr.Zero)
        {
            bridge.UdpSocketFree(currentHandle);
        }

        GC.SuppressFinalize(this);
    }

    ~RustUdpSocket()
    {
        Dispose();
    }
}

public sealed class RustFileServer : IDisposable
{
    private readonly ClipPlusFfiBridge bridge;
    private readonly ReaderWriterLockSlim handleLock = new();
    private IntPtr handle;
    private int disposed;

    internal RustFileServer(ClipPlusFfiBridge bridge, IntPtr handle)
    {
        this.bridge = bridge;
        this.handle = handle;
    }

    public int LocalPort
    {
        get
        {
            handleLock.EnterReadLock();
            try
            {
                return handle == IntPtr.Zero ? 0 : bridge.FileServerLocalPort(handle);
            }
            finally
            {
                handleLock.ExitReadLock();
            }
        }
    }

    public bool RegisterTransfer(string transferId, IReadOnlyList<string> sourcePaths)
    {
        handleLock.EnterReadLock();
        try
        {
            return handle != IntPtr.Zero && bridge.FileServerRegisterTransfer(handle, transferId, sourcePaths);
        }
        finally
        {
            handleLock.ExitReadLock();
        }
    }

    public ulong ServeNext(string tempDirectory)
    {
        handleLock.EnterReadLock();
        try
        {
            return handle == IntPtr.Zero ? 0 : bridge.FileServerServeNext(handle, tempDirectory);
        }
        finally
        {
            handleLock.ExitReadLock();
        }
    }

    public FileTreeDownloadResult? ServeNextTree()
    {
        handleLock.EnterReadLock();
        try
        {
            return handle == IntPtr.Zero ? null : bridge.FileServerServeNextTree(handle);
        }
        finally
        {
            handleLock.ExitReadLock();
        }
    }

    public void Dispose()
    {
        if (System.Threading.Interlocked.Exchange(ref disposed, 1) == 1)
        {
            return;
        }

        handleLock.EnterWriteLock();
        try
        {
            var currentHandle = handle;
            handle = IntPtr.Zero;
            if (currentHandle != IntPtr.Zero)
            {
                bridge.FileServerFree(currentHandle);
            }
        }
        finally
        {
            handleLock.ExitWriteLock();
            handleLock.Dispose();
        }

        GC.SuppressFinalize(this);
    }

    ~RustFileServer()
    {
        Dispose();
    }
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
    private delegate IntPtr CreateImageOfferMessageJsonDelegate(
        IntPtr groupId,
        IntPtr senderDeviceId,
        IntPtr senderDeviceName,
        IntPtr transferId,
        IntPtr imageBytes,
        UIntPtr imageLen,
        ushort archivePort);

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
    private delegate ulong ServeFileArchiveToSocketDelegate(
        UIntPtr socket,
        IntPtr sourcePathsJson,
        IntPtr archivePath);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool DownloadFileArchiveDelegate(
        IntPtr host,
        ushort port,
        IntPtr transferId,
        IntPtr destinationPath);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr DownloadFileTreeDelegate(
        IntPtr host,
        ushort port,
        IntPtr transferId,
        IntPtr destinationDirectory);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr UdpSocketBindDelegate(ushort bindPort);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void UdpSocketFreeDelegate(IntPtr handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ushort UdpSocketLocalPortDelegate(IntPtr handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool UdpSocketSendToDelegate(
        IntPtr handle,
        IntPtr payload,
        UIntPtr payloadLen,
        IntPtr targetHost,
        ushort targetPort);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate UIntPtr UdpSocketRecvDelegate(
        IntPtr handle,
        IntPtr buffer,
        UIntPtr bufferLen,
        IntPtr sourceHostBuffer,
        UIntPtr sourceHostLen,
        out ushort sourcePort);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr FileServerBindDelegate(ushort bindPort);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void FileServerFreeDelegate(IntPtr handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ushort FileServerLocalPortDelegate(IntPtr handle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool FileServerRegisterTransferDelegate(
        IntPtr handle,
        IntPtr transferId,
        IntPtr sourcePathsJson);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong FileServerServeNextDelegate(
        IntPtr handle,
        IntPtr tempDirectory);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr FileServerServeNextTreeDelegate(IntPtr handle);

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
    private readonly CreateImageOfferMessageJsonDelegate createImageOfferMessageJson;
    private readonly CreateFileOfferMessageJsonDelegate createFileOfferMessageJson;
    private readonly WriteFileArchiveZipDelegate writeFileArchiveZip;
    private readonly ServeFileArchiveToSocketDelegate serveFileArchiveToSocket;
    private readonly DownloadFileArchiveDelegate downloadFileArchive;
    private readonly DownloadFileTreeDelegate downloadFileTree;
    private readonly UdpSocketBindDelegate udpSocketBind;
    private readonly UdpSocketFreeDelegate udpSocketFree;
    private readonly UdpSocketLocalPortDelegate udpSocketLocalPort;
    private readonly UdpSocketSendToDelegate udpSocketSendTo;
    private readonly UdpSocketRecvDelegate udpSocketRecv;
    private readonly FileServerBindDelegate fileServerBind;
    private readonly FileServerFreeDelegate fileServerFree;
    private readonly FileServerLocalPortDelegate fileServerLocalPort;
    private readonly FileServerRegisterTransferDelegate fileServerRegisterTransfer;
    private readonly FileServerServeNextDelegate fileServerServeNext;
    private readonly FileServerServeNextTreeDelegate fileServerServeNextTree;
    private readonly CreateTextMessageJsonDelegate createTrustMessageJson;
    private readonly FreeStringDelegate freeString;

    private static readonly JsonSerializerOptions TreeSummaryJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private ClipPlusFfiBridge(
        DeriveGroupIdDelegate deriveGroupId,
        CreateHelloMessageJsonDelegate createHelloMessageJson,
        CreateTextMessageJsonDelegate createTextMessageJson,
        CreateImageMessageJsonDelegate createImageMessageJson,
        CreateImageOfferMessageJsonDelegate createImageOfferMessageJson,
        CreateFileOfferMessageJsonDelegate createFileOfferMessageJson,
        WriteFileArchiveZipDelegate writeFileArchiveZip,
        ServeFileArchiveToSocketDelegate serveFileArchiveToSocket,
        DownloadFileArchiveDelegate downloadFileArchive,
        DownloadFileTreeDelegate downloadFileTree,
        UdpSocketBindDelegate udpSocketBind,
        UdpSocketFreeDelegate udpSocketFree,
        UdpSocketLocalPortDelegate udpSocketLocalPort,
        UdpSocketSendToDelegate udpSocketSendTo,
        UdpSocketRecvDelegate udpSocketRecv,
        FileServerBindDelegate fileServerBind,
        FileServerFreeDelegate fileServerFree,
        FileServerLocalPortDelegate fileServerLocalPort,
        FileServerRegisterTransferDelegate fileServerRegisterTransfer,
        FileServerServeNextDelegate fileServerServeNext,
        FileServerServeNextTreeDelegate fileServerServeNextTree,
        CreateTextMessageJsonDelegate createTrustMessageJson,
        FreeStringDelegate freeString)
    {
        this.deriveGroupId = deriveGroupId;
        this.createHelloMessageJson = createHelloMessageJson;
        this.createTextMessageJson = createTextMessageJson;
        this.createImageMessageJson = createImageMessageJson;
        this.createImageOfferMessageJson = createImageOfferMessageJson;
        this.createFileOfferMessageJson = createFileOfferMessageJson;
        this.writeFileArchiveZip = writeFileArchiveZip;
        this.serveFileArchiveToSocket = serveFileArchiveToSocket;
        this.downloadFileArchive = downloadFileArchive;
        this.downloadFileTree = downloadFileTree;
        this.udpSocketBind = udpSocketBind;
        this.udpSocketFree = udpSocketFree;
        this.udpSocketLocalPort = udpSocketLocalPort;
        this.udpSocketSendTo = udpSocketSendTo;
        this.udpSocketRecv = udpSocketRecv;
        this.fileServerBind = fileServerBind;
        this.fileServerFree = fileServerFree;
        this.fileServerLocalPort = fileServerLocalPort;
        this.fileServerRegisterTransfer = fileServerRegisterTransfer;
        this.fileServerServeNext = fileServerServeNext;
        this.fileServerServeNextTree = fileServerServeNextTree;
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
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_image_offer_message_json", out var createImageOfferMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_create_file_offer_message_json", out var createFileOfferMessageJsonSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_write_file_archive_zip", out var writeFileArchiveZipSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_serve_file_archive_to_socket", out var serveFileArchiveToSocketSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_download_file_archive", out var downloadFileArchiveSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_download_file_tree", out var downloadFileTreeSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_bind", out var udpSocketBindSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_free", out var udpSocketFreeSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_local_port", out var udpSocketLocalPortSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_send_to", out var udpSocketSendToSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_recv", out var udpSocketRecvSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_bind", out var fileServerBindSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_free", out var fileServerFreeSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_local_port", out var fileServerLocalPortSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_register_transfer", out var fileServerRegisterTransferSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_serve_next", out var fileServerServeNextSymbol)
                || !NativeLibrary.TryGetExport(handle, "clipplus_file_server_serve_next_tree", out var fileServerServeNextTreeSymbol)
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
                Marshal.GetDelegateForFunctionPointer<CreateImageOfferMessageJsonDelegate>(createImageOfferMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateFileOfferMessageJsonDelegate>(createFileOfferMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<WriteFileArchiveZipDelegate>(writeFileArchiveZipSymbol),
                Marshal.GetDelegateForFunctionPointer<ServeFileArchiveToSocketDelegate>(serveFileArchiveToSocketSymbol),
                Marshal.GetDelegateForFunctionPointer<DownloadFileArchiveDelegate>(downloadFileArchiveSymbol),
                Marshal.GetDelegateForFunctionPointer<DownloadFileTreeDelegate>(downloadFileTreeSymbol),
                Marshal.GetDelegateForFunctionPointer<UdpSocketBindDelegate>(udpSocketBindSymbol),
                Marshal.GetDelegateForFunctionPointer<UdpSocketFreeDelegate>(udpSocketFreeSymbol),
                Marshal.GetDelegateForFunctionPointer<UdpSocketLocalPortDelegate>(udpSocketLocalPortSymbol),
                Marshal.GetDelegateForFunctionPointer<UdpSocketSendToDelegate>(udpSocketSendToSymbol),
                Marshal.GetDelegateForFunctionPointer<UdpSocketRecvDelegate>(udpSocketRecvSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerBindDelegate>(fileServerBindSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerFreeDelegate>(fileServerFreeSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerLocalPortDelegate>(fileServerLocalPortSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerRegisterTransferDelegate>(fileServerRegisterTransferSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerServeNextDelegate>(fileServerServeNextSymbol),
                Marshal.GetDelegateForFunctionPointer<FileServerServeNextTreeDelegate>(fileServerServeNextTreeSymbol),
                Marshal.GetDelegateForFunctionPointer<CreateTextMessageJsonDelegate>(createTrustMessageJsonSymbol),
                Marshal.GetDelegateForFunctionPointer<FreeStringDelegate>(freeSymbol)
            );
        }

        return null;
    }

    internal static IReadOnlyList<string> LoadDiagnostics()
    {
        var lines = new List<string>();
        var assembly = typeof(ClipPlusFfiBridge).Assembly;
        lines.Add($"assembly_name={assembly.GetName().Name}");
        lines.Add($"os_architecture={RuntimeInformation.OSArchitecture}");
        lines.Add($"process_architecture={RuntimeInformation.ProcessArchitecture}");
        lines.Add($"base_directory={AppContext.BaseDirectory}");
        lines.Add($"resource_names={string.Join(",", assembly.GetManifestResourceNames())}");

        foreach (var candidatePath in LibraryCandidatePaths())
        {
            lines.Add($"candidate={candidatePath}");
            if (!File.Exists(candidatePath))
            {
                lines.Add("candidate_exists=false");
                continue;
            }

            lines.Add($"candidate_exists=true length={new FileInfo(candidatePath).Length}");
            IntPtr handle;
            try
            {
                handle = NativeLibrary.Load(candidatePath);
                lines.Add("native_load=ok");
            }
            catch (Exception exception)
            {
                lines.Add($"native_load=failed {exception.GetType().Name}: {exception.Message}");
                continue;
            }

            try
            {
                lines.Add($"export_clipplus_derive_group_id={NativeLibrary.TryGetExport(handle, "clipplus_derive_group_id", out _)}");
                lines.Add($"export_clipplus_create_image_offer_message_json={NativeLibrary.TryGetExport(handle, "clipplus_create_image_offer_message_json", out _)}");
                lines.Add($"export_clipplus_download_file_archive={NativeLibrary.TryGetExport(handle, "clipplus_download_file_archive", out _)}");
                lines.Add($"export_clipplus_download_file_tree={NativeLibrary.TryGetExport(handle, "clipplus_download_file_tree", out _)}");
                lines.Add($"export_clipplus_udp_socket_bind={NativeLibrary.TryGetExport(handle, "clipplus_udp_socket_bind", out _)}");
                lines.Add($"export_clipplus_file_server_bind={NativeLibrary.TryGetExport(handle, "clipplus_file_server_bind", out _)}");
                lines.Add($"export_clipplus_file_server_register_transfer={NativeLibrary.TryGetExport(handle, "clipplus_file_server_register_transfer", out _)}");
                lines.Add($"export_clipplus_file_server_serve_next={NativeLibrary.TryGetExport(handle, "clipplus_file_server_serve_next", out _)}");
                lines.Add($"export_clipplus_file_server_serve_next_tree={NativeLibrary.TryGetExport(handle, "clipplus_file_server_serve_next_tree", out _)}");
                lines.Add($"export_clipplus_free_string={NativeLibrary.TryGetExport(handle, "clipplus_free_string", out _)}");
            }
            finally
            {
                NativeLibrary.Free(handle);
            }
        }

        return lines;
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

    public string? CreateImageOfferMessageJson(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string transferId,
        byte[] pngData,
        int archivePort)
    {
        if (pngData.Length == 0 || archivePort <= 0 || archivePort > ushort.MaxValue)
        {
            return null;
        }

        var groupIdPointer = Marshal.StringToCoTaskMemUTF8(groupId);
        var senderDeviceIdPointer = Marshal.StringToCoTaskMemUTF8(senderDeviceId);
        var senderDeviceNamePointer = Marshal.StringToCoTaskMemUTF8(senderDeviceName);
        var transferIdPointer = Marshal.StringToCoTaskMemUTF8(transferId);
        var imageHandle = GCHandle.Alloc(pngData, GCHandleType.Pinned);
        try
        {
            return TakeOwnedString(createImageOfferMessageJson(
                groupIdPointer,
                senderDeviceIdPointer,
                senderDeviceNamePointer,
                transferIdPointer,
                imageHandle.AddrOfPinnedObject(),
                new UIntPtr((ulong)pngData.LongLength),
                (ushort)archivePort));
        }
        finally
        {
            imageHandle.Free();
            Marshal.FreeCoTaskMem(groupIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceIdPointer);
            Marshal.FreeCoTaskMem(senderDeviceNamePointer);
            Marshal.FreeCoTaskMem(transferIdPointer);
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

    public ulong ServeFileArchiveToSocket(IntPtr socket, IReadOnlyList<string> sourcePaths, string archivePath)
    {
        if (socket == IntPtr.Zero || string.IsNullOrWhiteSpace(archivePath))
        {
            return 0;
        }

        var sourcePathsJson = JsonSerializer.Serialize(sourcePaths);
        var sourcePathsJsonPointer = Marshal.StringToCoTaskMemUTF8(sourcePathsJson);
        var archivePathPointer = Marshal.StringToCoTaskMemUTF8(archivePath);
        try
        {
            return serveFileArchiveToSocket(
                new UIntPtr((ulong)socket.ToInt64()),
                sourcePathsJsonPointer,
                archivePathPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(sourcePathsJsonPointer);
            Marshal.FreeCoTaskMem(archivePathPointer);
        }
    }

    public bool DownloadFileArchive(string host, int port, string transferId, string destinationPath)
    {
        if (string.IsNullOrWhiteSpace(host)
            || string.IsNullOrWhiteSpace(transferId)
            || string.IsNullOrWhiteSpace(destinationPath)
            || port <= 0
            || port > ushort.MaxValue)
        {
            return false;
        }

        var hostPointer = Marshal.StringToCoTaskMemUTF8(host);
        var transferIdPointer = Marshal.StringToCoTaskMemUTF8(transferId);
        var destinationPathPointer = Marshal.StringToCoTaskMemUTF8(destinationPath);
        try
        {
            return downloadFileArchive(
                hostPointer,
                (ushort)port,
                transferIdPointer,
                destinationPathPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(hostPointer);
            Marshal.FreeCoTaskMem(transferIdPointer);
            Marshal.FreeCoTaskMem(destinationPathPointer);
        }
    }

    public FileTreeDownloadResult? DownloadFileTree(string host, int port, string transferId, string destinationDirectory)
    {
        if (string.IsNullOrWhiteSpace(host)
            || string.IsNullOrWhiteSpace(transferId)
            || string.IsNullOrWhiteSpace(destinationDirectory)
            || port <= 0
            || port > ushort.MaxValue)
        {
            return null;
        }

        var hostPointer = Marshal.StringToCoTaskMemUTF8(host);
        var transferIdPointer = Marshal.StringToCoTaskMemUTF8(transferId);
        var destinationDirectoryPointer = Marshal.StringToCoTaskMemUTF8(destinationDirectory);
        try
        {
            return TakeOwnedTreeSummary(downloadFileTree(
                hostPointer,
                (ushort)port,
                transferIdPointer,
                destinationDirectoryPointer));
        }
        finally
        {
            Marshal.FreeCoTaskMem(hostPointer);
            Marshal.FreeCoTaskMem(transferIdPointer);
            Marshal.FreeCoTaskMem(destinationDirectoryPointer);
        }
    }

    public RustUdpSocket? OpenUdpSocket(int bindPort)
    {
        if (bindPort < 0 || bindPort > ushort.MaxValue)
        {
            return null;
        }

        var handle = udpSocketBind((ushort)bindPort);
        return handle == IntPtr.Zero ? null : new RustUdpSocket(this, handle);
    }

    internal int UdpSocketLocalPort(IntPtr handle)
    {
        return udpSocketLocalPort(handle);
    }

    internal bool UdpSocketSendTo(IntPtr handle, byte[] payload, string targetHost, int targetPort)
    {
        if (payload.Length == 0 || string.IsNullOrWhiteSpace(targetHost) || targetPort <= 0 || targetPort > ushort.MaxValue)
        {
            return false;
        }

        var payloadHandle = GCHandle.Alloc(payload, GCHandleType.Pinned);
        var targetHostPointer = Marshal.StringToCoTaskMemUTF8(targetHost);
        try
        {
            return udpSocketSendTo(
                handle,
                payloadHandle.AddrOfPinnedObject(),
                new UIntPtr((ulong)payload.LongLength),
                targetHostPointer,
                (ushort)targetPort);
        }
        finally
        {
            payloadHandle.Free();
            Marshal.FreeCoTaskMem(targetHostPointer);
        }
    }

    internal RustUdpDatagram? UdpSocketReceive(IntPtr handle)
    {
        var payload = new byte[65_535];
        var sourceHostBytes = new byte[64];
        var payloadHandle = GCHandle.Alloc(payload, GCHandleType.Pinned);
        var sourceHostHandle = GCHandle.Alloc(sourceHostBytes, GCHandleType.Pinned);
        try
        {
            var byteCount = udpSocketRecv(
                handle,
                payloadHandle.AddrOfPinnedObject(),
                new UIntPtr((ulong)payload.LongLength),
                sourceHostHandle.AddrOfPinnedObject(),
                new UIntPtr((ulong)sourceHostBytes.LongLength),
                out var sourcePort);
            if (byteCount == UIntPtr.Zero)
            {
                return null;
            }

            var length = checked((int)byteCount.ToUInt64());
            var terminatorIndex = Array.IndexOf(sourceHostBytes, (byte)0);
            if (terminatorIndex <= 0)
            {
                return null;
            }

            var sourceHost = Encoding.UTF8.GetString(sourceHostBytes, 0, terminatorIndex);
            return new RustUdpDatagram(payload.Take(length).ToArray(), sourceHost, sourcePort);
        }
        finally
        {
            payloadHandle.Free();
            sourceHostHandle.Free();
        }
    }

    internal void UdpSocketFree(IntPtr handle)
    {
        udpSocketFree(handle);
    }

    public RustFileServer? OpenFileServer(int bindPort)
    {
        if (bindPort < 0 || bindPort > ushort.MaxValue)
        {
            return null;
        }

        var handle = fileServerBind((ushort)bindPort);
        return handle == IntPtr.Zero ? null : new RustFileServer(this, handle);
    }

    internal int FileServerLocalPort(IntPtr handle)
    {
        return fileServerLocalPort(handle);
    }

    internal bool FileServerRegisterTransfer(IntPtr handle, string transferId, IReadOnlyList<string> sourcePaths)
    {
        if (string.IsNullOrWhiteSpace(transferId) || sourcePaths.Count == 0)
        {
            return false;
        }

        var sourcePathsJson = JsonSerializer.Serialize(sourcePaths);
        var transferIdPointer = Marshal.StringToCoTaskMemUTF8(transferId);
        var sourcePathsJsonPointer = Marshal.StringToCoTaskMemUTF8(sourcePathsJson);
        try
        {
            return fileServerRegisterTransfer(handle, transferIdPointer, sourcePathsJsonPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(transferIdPointer);
            Marshal.FreeCoTaskMem(sourcePathsJsonPointer);
        }
    }

    internal ulong FileServerServeNext(IntPtr handle, string tempDirectory)
    {
        if (string.IsNullOrWhiteSpace(tempDirectory))
        {
            return 0;
        }

        var tempDirectoryPointer = Marshal.StringToCoTaskMemUTF8(tempDirectory);
        try
        {
            return fileServerServeNext(handle, tempDirectoryPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(tempDirectoryPointer);
        }
    }

    internal FileTreeDownloadResult? FileServerServeNextTree(IntPtr handle)
    {
        return TakeOwnedTreeSummary(fileServerServeNextTree(handle));
    }

    internal void FileServerFree(IntPtr handle)
    {
        fileServerFree(handle);
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

    private FileTreeDownloadResult? TakeOwnedTreeSummary(IntPtr resultPointer)
    {
        var json = TakeOwnedString(resultPointer);
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        var result = JsonSerializer.Deserialize<FileTreeDownloadResult>(json, TreeSummaryJsonOptions);
        if (result is null || result.TopLevelPaths.Count == 0)
        {
            return null;
        }

        return result;
    }

    private static IEnumerable<string> LibraryCandidatePaths()
    {
        var environmentPath = Environment.GetEnvironmentVariable("CLIPPLUS_FFI_LIBRARY_PATH");
        if (!string.IsNullOrWhiteSpace(environmentPath))
        {
            yield return environmentPath;
        }

        yield return Path.Combine(AppContext.BaseDirectory, "clipplus_ffi.dll");
        var embeddedLibraryPath = ExtractEmbeddedLibrary();
        if (!string.IsNullOrWhiteSpace(embeddedLibraryPath))
        {
            yield return embeddedLibraryPath;
        }
        yield return "clipplus_ffi.dll";
        yield return "clipplus_ffi";
    }

    private static string? ExtractEmbeddedLibrary()
    {
        var assembly = typeof(ClipPlusFfiBridge).Assembly;
        const string resourceName = "clipplus_ffi.dll";
        using var resourceStream = assembly.GetManifestResourceStream(resourceName);
        if (resourceStream is null)
        {
            return null;
        }

        var extractionDirectory = Path.Combine(Path.GetTempPath(), "ClipPlus", assembly.GetName().Version?.ToString() ?? "dev");
        Directory.CreateDirectory(extractionDirectory);
        var resourceLength = resourceStream.CanSeek ? resourceStream.Length : 0;
        var extractionPath = Path.Combine(
            extractionDirectory,
            $"clipplus_ffi-{Environment.ProcessId}-{resourceLength}.dll");
        if (File.Exists(extractionPath) && new FileInfo(extractionPath).Length > 0)
        {
            return extractionPath;
        }

        using (var output = new FileStream(extractionPath, FileMode.Create, FileAccess.Write, FileShare.Read))
        {
            resourceStream.CopyTo(output);
        }

        return extractionPath;
    }
}
