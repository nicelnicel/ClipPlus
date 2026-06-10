using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Windows.Threading;
using ClipPlus.Windows.Clipboard;
using ClipPlus.Windows.Diagnostics;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Sync;

public sealed class UdpTextSyncService : IDisposable
{
    private const int Port = 47_631;

    private readonly SettingsState state;
    private readonly NativeClipboard clipboard = new();
    private readonly ClipPlusLogger logger;
    private readonly Dispatcher dispatcher;
    private readonly DispatcherTimer timer;
    private readonly string deviceId;
    private readonly string deviceName;
    private readonly bool autoTrustPeers;
    private readonly IReadOnlyList<string> peerHosts;

    private UdpClient? receiveClient;
    private UdpClient? sendClient;
    private CancellationTokenSource? cancellation;
    private string? lastLocalText;
    private string? lastRemoteText;
    private string? lastLocalImageHash;
    private string? lastRemoteImageHash;
    private int tickCount;

    public UdpTextSyncService(SettingsState state, ClipPlusLogger logger, Dispatcher dispatcher)
    {
        this.state = state;
        this.logger = logger;
        this.dispatcher = dispatcher;
        deviceId = LoadOrCreateDeviceId();
        deviceName = Environment.MachineName;
        autoTrustPeers = Environment.GetEnvironmentVariable("CLIPPLUS_AUTO_TRUST") == "1";
        peerHosts = (Environment.GetEnvironmentVariable("CLIPPLUS_PEER_HOSTS") ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(750)
        };
        timer.Tick += (_, _) => PollClipboardAndBroadcast();
    }

    public void Start()
    {
        if (receiveClient is not null)
        {
            return;
        }

        ApplyEnvironmentKeyIfNeeded();

        try
        {
            cancellation = new CancellationTokenSource();
            receiveClient = new UdpClient
            {
                EnableBroadcast = true
            };
            receiveClient.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            receiveClient.Client.Bind(new IPEndPoint(IPAddress.Any, Port));

            sendClient = new UdpClient
            {
                EnableBroadcast = true
            };

            _ = Task.Run(() => ReceiveLoopAsync(cancellation.Token));
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
        timer.Stop();
        cancellation?.Cancel();
        receiveClient?.Dispose();
        sendClient?.Dispose();
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
        while (!token.IsCancellationRequested && receiveClient is not null)
        {
            try
            {
                var result = await receiveClient.ReceiveAsync(token);
                var json = Encoding.UTF8.GetString(result.Buffer);
                var message = ClipPlusMessage.FromJson(json);
                await dispatcher.InvokeAsync(() => Handle(message));
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
        if (!state.SharedKeyConfigured || !state.SharingEnabled)
        {
            return;
        }

        tickCount++;
        if (tickCount % 4 == 0)
        {
            SendHello();
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

    private void Handle(ClipPlusMessage message)
    {
        if (!state.SharedKeyConfigured
            || message.ProtocolVersion != 1
            || !string.Equals(message.GroupId, state.SharedGroupId, StringComparison.Ordinal)
            || string.Equals(message.SenderDeviceId, deviceId, StringComparison.Ordinal))
        {
            return;
        }

        switch (message.Kind)
        {
            case ClipPlusMessageKind.Hello:
                state.MarkPeerPending(message.SenderDeviceId, message.SenderDeviceName);
                if (autoTrustPeers)
                {
                    state.ApprovePendingPeers();
                }
                logger.Info($"peer hello device_id_prefix={message.SenderDeviceId[..Math.Min(8, message.SenderDeviceId.Length)]}");
                break;
            case ClipPlusMessageKind.Text:
                if (!state.SharingEnabled
                    || !state.IsPeerTrusted(message.SenderDeviceId)
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
                    || !state.IsPeerTrusted(message.SenderDeviceId)
                    || imageData is null
                    || imageData.Length > ClipPlusMessage.MaxInlineImageBytes
                    || string.IsNullOrEmpty(message.ImageContentHash))
                {
                    return;
                }

                lastRemoteImageHash = message.ImageContentHash;
                lastLocalImageHash = message.ImageContentHash;
                clipboard.WritePngImageData(imageData);
                state.LastStatusMessage = "已接收远端图片剪贴板";
                logger.Info($"received image clipboard byte_count={imageData.Length}");
                break;
        }
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
    }

    private void Send(ClipPlusMessage message)
    {
        var client = receiveClient ?? sendClient;
        if (client is null)
        {
            return;
        }

        var bytes = Encoding.UTF8.GetBytes(message.ToJson());
        try
        {
            _ = client.SendAsync(bytes, bytes.Length, new IPEndPoint(IPAddress.Broadcast, Port));
            foreach (var peerHost in peerHosts)
            {
                if (IPAddress.TryParse(peerHost, out var address))
                {
                    _ = client.SendAsync(bytes, bytes.Length, new IPEndPoint(address, Port));
                }
            }
        }
        catch (Exception error)
        {
            logger.Error($"send failed: {error.Message}");
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
