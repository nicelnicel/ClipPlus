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
}
