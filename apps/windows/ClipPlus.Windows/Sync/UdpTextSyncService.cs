using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Windows.Threading;
using ClipPlus.Windows.Clipboard;
using ClipPlus.Windows.CoreBridge;
using ClipPlus.Windows.Diagnostics;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Sync;

public sealed class UdpTextSyncService : IDisposable
{
    private const int Port = 47_631;
    private const int ArchivePort = 47_632;

    private readonly SettingsState state;
    private readonly NativeClipboard clipboard = new();
    private readonly ClipPlusLogger logger;
    private readonly Dispatcher dispatcher;
    private readonly DispatcherTimer timer;
    private readonly string deviceId;
    private readonly string deviceName;
    private readonly IReadOnlyList<string> peerHosts;
    private readonly object udpSocketLock = new();

    private RustUdpSocket? udpSocket;
    private RustFileServer? fileServer;
    private CancellationTokenSource? cancellation;
    private string? lastLocalText;
    private string? lastRemoteText;
    private string? lastLocalImageHash;
    private string? lastRemoteImageHash;
    private string? lastLocalFileSignature;
    private int tickCount;

    public UdpTextSyncService(SettingsState state, ClipPlusLogger logger, Dispatcher dispatcher)
    {
        this.state = state;
        this.logger = logger;
        this.dispatcher = dispatcher;
        deviceId = LoadOrCreateDeviceId();
        deviceName = Environment.MachineName;
        peerHosts = (Environment.GetEnvironmentVariable("CLIPPLUS_PEER_HOSTS") ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        state.PeerApproved += SendTrust;
        state.RemoteFileReceiveRequested += DownloadRemoteFileOffer;
        timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(750)
        };
        timer.Tick += (_, _) => PollClipboardAndBroadcast();
        _ = RefreshLocalDeviceInfoAsync();
    }

    public void Start()
    {
        if (udpSocket is not null)
        {
            return;
        }

        ApplyEnvironmentKeyIfNeeded();

        try
        {
            cancellation = new CancellationTokenSource();
            var bridge = new ClipPlus.Windows.CoreBridge.CoreBridge();
            udpSocket = bridge.OpenUdpSocket(Port)
                ?? throw new InvalidOperationException("Rust UDP socket is unavailable.");
            fileServer = bridge.OpenFileServer(ArchivePort)
                ?? throw new InvalidOperationException("Rust file server is unavailable.");
            if (fileServer.LocalPort != ArchivePort)
            {
                throw new InvalidOperationException("Rust file server bound an unexpected port.");
            }

            _ = Task.Run(() => ReceiveLoopAsync(cancellation.Token));
            _ = Task.Run(() => FileArchiveLoop(cancellation.Token));
            timer.Start();
            SendHello();
            logger.Info($"sync service started on UDP {Port}");
        }
        catch (Exception error)
        {
            state.LastStatusMessage = "同步服务启动失败";
            logger.Error($"sync service start failed: {error.Message}");
        }
    }

    public void Dispose()
    {
        state.PeerApproved -= SendTrust;
        state.RemoteFileReceiveRequested -= DownloadRemoteFileOffer;
        timer.Stop();
        cancellation?.Cancel();
        WakeFileServer();
        fileServer?.Dispose();
        fileServer = null;
        RustUdpSocket? socketToDispose;
        lock (udpSocketLock)
        {
            socketToDispose = udpSocket;
            udpSocket = null;
        }

        socketToDispose?.Dispose();
        cancellation?.Dispose();
    }

    private void ApplyEnvironmentKeyIfNeeded()
    {
        var sharedKey = Environment.GetEnvironmentVariable("CLIPPLUS_SHARED_KEY");
        if (!state.RequiresKeySetup || string.IsNullOrWhiteSpace(sharedKey))
        {
            return;
        }

        try
        {
            state.UpdateSharedKey(sharedKey, sharedKey);
            logger.Info("shared key configured from environment");
        }
        catch (Exception error)
        {
            logger.Error($"environment shared key rejected: {error.Message}");
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                RustUdpDatagram? datagram;
                lock (udpSocketLock)
                {
                    if (udpSocket is null)
                    {
                        return;
                    }

                    datagram = udpSocket.Receive();
                }

                if (datagram is null)
                {
                    continue;
                }

                var json = Encoding.UTF8.GetString(datagram.Payload);
                var message = ClipPlusMessage.FromJson(json);
                var sourceHost = datagram.SourceHost;
                await dispatcher.InvokeAsync(() => Handle(message, sourceHost));
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }
            catch (Exception error)
            {
                logger.Error($"receive loop error: {error.Message}");
            }
        }
    }

    private void PollClipboardAndBroadcast()
    {
        state.PurgeExpiredConnectedPeers();
        if (!state.SharedKeyConfigured || !state.SharingEnabled)
        {
            return;
        }

        tickCount++;
        if (tickCount % 4 == 0)
        {
            SendHello();
        }

        if (!state.CanPublishClipboardContent)
        {
            return;
        }

        var filePaths = clipboard.ReadFilePaths();
        if (filePaths.Count > 0)
        {
            var signature = string.Join("|", filePaths.OrderBy(path => path, StringComparer.Ordinal));
            if (!string.Equals(signature, lastLocalFileSignature, StringComparison.Ordinal))
            {
                lastLocalFileSignature = signature;
                PublishFileOffer(filePaths);
            }

            return;
        }

        var text = clipboard.ReadText();
        if (!string.IsNullOrEmpty(text)
            && !string.Equals(text, lastLocalText, StringComparison.Ordinal)
            && !string.Equals(text, lastRemoteText, StringComparison.Ordinal))
        {
            lastLocalText = text;
            Send(ClipPlusMessage.CreateText(
                state.SharedGroupId,
                deviceId,
                deviceName,
                text
            ));
            state.LastStatusMessage = "已广播文本剪贴板";
            logger.Info($"published text clipboard byte_count={Encoding.UTF8.GetByteCount(text)}");
        }

        var pngData = clipboard.ReadPngImageData();
        var imageMessage = pngData is null
            ? null
            : ClipPlusMessage.CreateImage(
                state.SharedGroupId,
                deviceId,
                deviceName,
                pngData
            );
        if (imageMessage?.ImageContentHash is null
            || string.Equals(imageMessage.ImageContentHash, lastLocalImageHash, StringComparison.Ordinal)
            || string.Equals(imageMessage.ImageContentHash, lastRemoteImageHash, StringComparison.Ordinal))
        {
            return;
        }

        lastLocalImageHash = imageMessage.ImageContentHash;
        Send(imageMessage);
        state.LastStatusMessage = "已广播图片剪贴板";
        logger.Info($"published image clipboard byte_count={pngData!.Length}");
    }

    private string? LocalImageHashAfterClipboardWrite()
    {
        var writtenPngData = clipboard.ReadPngImageData();
        if (writtenPngData is null)
        {
            return null;
        }

        return ClipPlusMessage.CreateImage(
            state.SharedGroupId,
            deviceId,
            deviceName,
            writtenPngData
        )?.ImageContentHash;
    }

    private void Handle(ClipPlusMessage message, string sourceHost)
    {
        if (!state.SharedKeyConfigured
            || message.ProtocolVersion != 1
            || !string.Equals(message.GroupId, state.SharedGroupId, StringComparison.Ordinal)
            || string.Equals(message.SenderDeviceId, deviceId, StringComparison.Ordinal))
        {
            return;
        }

        state.RecordConnectedPeer(message.SenderDeviceId, message.SenderDeviceName, sourceHost);

        switch (message.Kind)
        {
            case ClipPlusMessageKind.Hello:
                if (state.TrustPeer(message.SenderDeviceId, message.SenderDeviceName))
                {
                    SendTrust(message.SenderDeviceId);
                    logger.Info($"peer hello trusted device_id_prefix={message.SenderDeviceId[..Math.Min(8, message.SenderDeviceId.Length)]}");
                }
                else
                {
                    logger.Info($"peer hello device_id_prefix={message.SenderDeviceId[..Math.Min(8, message.SenderDeviceId.Length)]}");
                }
                break;
            case ClipPlusMessageKind.Trust:
                if (!string.Equals(message.ApprovedDeviceId, deviceId, StringComparison.Ordinal))
                {
                    return;
                }

                if (state.TrustPeer(message.SenderDeviceId, message.SenderDeviceName))
                {
                    logger.Info($"peer trust accepted device_id_prefix={message.SenderDeviceId[..Math.Min(8, message.SenderDeviceId.Length)]}");
                }
                break;
            case ClipPlusMessageKind.Text:
                if (!state.SharingEnabled
                    || string.IsNullOrEmpty(message.Text))
                {
                    return;
                }

                lastRemoteText = message.Text;
                lastLocalText = message.Text;
                clipboard.WriteText(message.Text);
                state.LastStatusMessage = "已接收远端文本剪贴板";
                logger.Info($"received text clipboard byte_count={Encoding.UTF8.GetByteCount(message.Text)}");
                break;
            case ClipPlusMessageKind.Image:
                var imageData = message.DecodedImageData;
                if (!state.SharingEnabled
                    || imageData is null
                    || imageData.Length > ClipPlusMessage.MaxInlineImageBytes
                    || string.IsNullOrEmpty(message.ImageContentHash))
                {
                    return;
                }

                lastRemoteImageHash = message.ImageContentHash;
                lastLocalImageHash = message.ImageContentHash;
                clipboard.WritePngImageData(imageData);
                lastLocalImageHash = LocalImageHashAfterClipboardWrite() ?? lastLocalImageHash;
                state.LastStatusMessage = "已接收远端图片剪贴板";
                logger.Info($"received image clipboard byte_count={imageData.Length}");
                break;
            case ClipPlusMessageKind.FileOffer:
                if (!state.SharingEnabled
                    || string.IsNullOrEmpty(message.TransferId)
                    || message.Files is null
                    || message.Files.Count == 0)
                {
                    return;
                }

                var totalBytes = message.Files.Sum(file => file.ByteSize);
                state.UpdateRemoteFileOffer(new RemoteFileOfferSummary(
                    TransferId: message.TransferId,
                    SourceDeviceId: message.SenderDeviceId,
                    SourceDeviceName: message.SenderDeviceName,
                    SourceHost: sourceHost,
                    FileCount: message.Files.Count,
                    TotalBytes: totalBytes
                ));
                logger.Info($"received file offer file_count={message.Files.Count} byte_count={totalBytes}");
                break;
        }
    }

    private void PublishFileOffer(IReadOnlyList<string> filePaths)
    {
        var transferId = Guid.NewGuid().ToString();
        if (fileServer?.RegisterTransfer(transferId, filePaths) != true)
        {
            state.LastStatusMessage = "文件广播失败";
            logger.Error("file transfer registration failed");
            return;
        }

        var items = filePaths.Select(CreateFileTransferItem).ToArray();
        Send(ClipPlusMessage.CreateFileOffer(
            state.SharedGroupId,
            deviceId,
            deviceName,
            transferId,
            items,
            ArchivePort
        ));
        state.LastStatusMessage = "已广播文件剪贴板";
        logger.Info($"published file offer file_count={items.Length}");
    }

    private static FileTransferItem CreateFileTransferItem(string path)
    {
        if (Directory.Exists(path))
        {
            return new FileTransferItem(
                RelativePath: Path.GetFileName(path),
                ByteSize: Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                    .Sum(file => new FileInfo(file).Length),
                IsDirectory: true
            );
        }

        return new FileTransferItem(
            RelativePath: Path.GetFileName(path),
            ByteSize: File.Exists(path) ? new FileInfo(path).Length : 0,
            IsDirectory: false
        );
    }

    private void FileArchiveLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                var server = fileServer;
                if (server is null)
                {
                    return;
                }

                var byteCount = server.ServeNext(Path.GetTempPath());
                if (token.IsCancellationRequested)
                {
                    return;
                }
                if (byteCount > 0)
                {
                    logger.Info($"served file archive byte_count={byteCount}");
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }
            catch (Exception error)
            {
                logger.Error($"file archive loop error: {error.Message}");
            }
        }
    }

    private void DownloadRemoteFileOffer(string transferId)
    {
        var offer = state.RemoteFileOffer;
        if (offer is null || !string.Equals(offer.TransferId, transferId, StringComparison.Ordinal))
        {
            return;
        }

        _ = Task.Run(async () => await DownloadRemoteFileOfferAsync(offer));
    }

    private async Task DownloadRemoteFileOfferAsync(RemoteFileOfferSummary offer)
    {
        var destinationPath = UniqueDownloadPath(offer.TransferId);
        try
        {
            if (!new ClipPlus.Windows.CoreBridge.CoreBridge().DownloadFileArchive(
                offer.SourceHost,
                ArchivePort,
                offer.TransferId,
                destinationPath))
            {
                if (File.Exists(destinationPath))
                {
                    File.Delete(destinationPath);
                }

                throw new InvalidOperationException("file transfer download failed");
            }

            var byteCount = new FileInfo(destinationPath).Length;
            await dispatcher.InvokeAsync(() =>
            {
                state.ClearRemoteFileOffer(offer.TransferId);
                state.LastStatusMessage = $"文件已接收到 {Path.GetFileName(destinationPath)}";
            });
            logger.Info($"downloaded file archive byte_count={byteCount}");
        }
        catch (Exception error)
        {
            await dispatcher.InvokeAsync(() => state.LastStatusMessage = "文件接收失败");
            logger.Error($"file transfer download failed: {error.Message}");
        }
    }

    private static string UniqueDownloadPath(string transferId)
    {
        var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        Directory.CreateDirectory(downloads);
        var candidate = Path.Combine(downloads, $"ClipPlus-Received-{transferId}.zip");
        var index = 2;
        while (File.Exists(candidate))
        {
            candidate = Path.Combine(downloads, $"ClipPlus-Received-{transferId}-{index}.zip");
            index++;
        }

        return candidate;
    }

    private void SendHello()
    {
        if (!state.SharedKeyConfigured)
        {
            return;
        }

        Send(ClipPlusMessage.CreateHello(
            state.SharedGroupId,
            deviceId,
            deviceName
        ));

        foreach (var trustedPeerId in state.TrustedPeerIds)
        {
            SendTrust(trustedPeerId);
        }
    }

    private void SendTrust(string approvedDeviceId)
    {
        if (!state.SharedKeyConfigured)
        {
            return;
        }

        Send(ClipPlusMessage.CreateTrust(
            state.SharedGroupId,
            deviceId,
            deviceName,
            approvedDeviceId
        ));
    }

    private void Send(ClipPlusMessage message)
    {
        var bytes = Encoding.UTF8.GetBytes(message.ToJson());
        try
        {
            lock (udpSocketLock)
            {
                if (udpSocket is null)
                {
                    return;
                }

                var targets = new HashSet<string>(StringComparer.Ordinal)
                {
                    IPAddress.Broadcast.ToString()
                };
                foreach (var peerHost in peerHosts)
                {
                    targets.Add(peerHost);
                }

                foreach (var peerHost in state.ConnectedRemotePeerSummaries.Select(peer => peer.IpAddress))
                {
                    targets.Add(peerHost);
                }

                foreach (var peerHost in targets)
                {
                    if (IPAddress.TryParse(peerHost, out var address))
                    {
                        _ = udpSocket.SendTo(bytes, address.ToString(), Port);
                    }
                }
            }
        }
        catch (Exception error)
        {
            logger.Error($"send failed: {error.Message}");
        }
    }

    private static string LocalIPv4Address()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(networkInterface =>
                networkInterface.OperationalStatus == OperationalStatus.Up
                && networkInterface.NetworkInterfaceType != NetworkInterfaceType.Loopback
                && networkInterface.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
            .SelectMany(networkInterface => networkInterface.GetIPProperties().UnicastAddresses)
            .Select(address => address.Address)
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
            .Select(address => address.ToString())
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        return candidates.FirstOrDefault(IsPrivateIPv4Address)
            ?? candidates.FirstOrDefault()
            ?? "未知 IP";
    }

    private static bool IsPrivateIPv4Address(string ipAddress)
    {
        var parts = ipAddress
            .Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => byte.TryParse(part, out var value) ? value : (byte?)null)
            .ToArray();
        if (parts.Length != 4 || parts.Any(part => part is null))
        {
            return false;
        }

        var first = parts[0]!.Value;
        var second = parts[1]!.Value;
        return first == 10
            || (first == 172 && second is >= 16 and <= 31)
            || (first == 192 && second == 168);
    }

    private async Task RefreshLocalDeviceInfoAsync()
    {
        var currentDeviceId = deviceId;
        var currentDeviceName = deviceName;
        var ipAddress = await Task.Run(LocalIPv4Address);
        await dispatcher.InvokeAsync(() => state.SetLocalDevice(
            currentDeviceId,
            currentDeviceName,
            ipAddress
        ));
    }

    private static void WakeFileServer()
    {
        try
        {
            using var client = new TcpClient();
            client.Connect(IPAddress.Loopback, ArchivePort);
            using var stream = client.GetStream();
            stream.Write(Encoding.UTF8.GetBytes("\n"));
        }
        catch
        {
            // Best-effort wakeup for a blocking Rust accept during shutdown.
        }
    }

    private static string LoadOrCreateDeviceId()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ClipPlus"
        );
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "device.id");

        if (File.Exists(path))
        {
            return File.ReadAllText(path).Trim();
        }

        var value = Guid.NewGuid().ToString();
        File.WriteAllText(path, value);
        return value;
    }
}
