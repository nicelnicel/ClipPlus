using System.Windows;
using ClipPlus.Windows.Diagnostics;
using ClipPlus.Windows.CoreBridge;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Startup;
using ClipPlus.Windows.Sync;
using ClipPlus.Windows.Tray;

namespace ClipPlus.Windows;

public partial class App : System.Windows.Application
{
    private TrayController? trayController;
    private UdpTextSyncService? syncService;
    private StartupManager? startupManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        CoreBridgeSmokeTest.RunIfRequested();

        startupManager = new StartupManager();
        var settings = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: startupManager.IsEnabled()
        );
        settings.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(SettingsState.StartupEnabled))
            {
                startupManager.SetEnabled(settings.StartupEnabled);
            }
        };
        trayController = new TrayController(settings);
        syncService = new UdpTextSyncService(settings, new ClipPlusLogger(), Dispatcher);
        syncService.Start();

        if (ShouldOpenSettingsWindow(
            settings,
            Environment.GetEnvironmentVariable("CLIPPLUS_SHOW_SETTINGS_ON_START") == "1"))
        {
            new SettingsWindow(settings).Show();
        }
    }

    public static bool ShouldOpenSettingsWindow(SettingsState settings, bool showSettingsRequested)
    {
        return settings.RequiresKeySetup || showSettingsRequested;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        syncService?.Dispose();
        trayController?.Dispose();
        base.OnExit(e);
    }
}
