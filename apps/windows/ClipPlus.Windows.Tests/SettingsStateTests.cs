using ClipPlus.Windows.Settings;
using Xunit;

namespace ClipPlus.Windows.Tests;

public sealed class SettingsStateTests
{
    [Fact]
    public void MissingKeyRequiresSetup()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.True(state.RequiresKeySetup);
    }

    [Fact]
    public void StartupToggleUpdatesState()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.StartupEnabled = true;

        Assert.True(state.StartupEnabled);
    }

    [Fact]
    public void SharedKeyStoresOnlyDerivedGroupIdentifier()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.UpdateSharedKey("clipplus-test-key", "clipplus-test-key");

        Assert.True(state.SharedKeyConfigured);
        Assert.Equal("OcePlqBkjK6NLJjtPRglTw", state.SharedGroupId);
        Assert.DoesNotContain("clipplus-test-key", state.SharedGroupId);
    }

    [Fact]
    public void MismatchedSharedKeyConfirmationFails()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.Throws<ArgumentException>(() => state.UpdateSharedKey("clipplus-test-key", "other-key"));
        Assert.False(state.SharedKeyConfigured);
        Assert.True(state.RequiresKeySetup);
    }

    [Fact]
    public void PendingPeerMustBeApprovedBeforeSync()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.MarkPeerPending("mac-device", "MacBook");

        Assert.Equal(1, state.PendingPeerCount);
        Assert.False(state.IsPeerTrusted("mac-device"));

        state.ApprovePendingPeers();

        Assert.Equal(0, state.PendingPeerCount);
        Assert.True(state.IsPeerTrusted("mac-device"));
    }

    [Fact]
    public void ClipPlusMessageRoundTripsTextPayload()
    {
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateText(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            text: "hello from windows"
        );

        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Text, decoded.Kind);
        Assert.Equal(1, decoded.ProtocolVersion);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("hello from windows", decoded.Text);
    }
}
