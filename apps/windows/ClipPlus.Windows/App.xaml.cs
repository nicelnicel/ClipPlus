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
    private SingleInstanceLock? singleInstanceLock;
    private TrayController? trayController;
    private UdpTextSyncService? syncService;
    private StartupManager? startupManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        singleInstanceLock = SingleInstanceLock.AcquireDefault();
        if (singleInstanceLock is null)
        {
            Shutdown();
            return;
        }

        base.OnStartup(e);

        CoreBridgeSmokeTest.RunIfRequested();

        startupManager = new StartupManager();
        var settingsStore = new SettingsStore();
        var persistedSettings = settingsStore.Load();
        var settings = new SettingsState(
            sharedKeyConfigured: persistedSettings.SharedKeyConfigured,
            sharingEnabled: persistedSettings.SharingEnabled,
            startupEnabled: startupManager.IsEnabled(),
            sharedGroupId: persistedSettings.SharedGroupId,
            sharedKeyInput: persistedSettings.SharedKeyInput
        );
        settings.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(SettingsState.StartupEnabled))
            {
                startupManager.SetEnabled(settings.StartupEnabled);
            }

            if (args.PropertyName == nameof(SettingsState.SharedKeyConfigured)
                || args.PropertyName == nameof(SettingsState.SharingEnabled)
                || args.PropertyName == nameof(SettingsState.SharedGroupId))
            {
                settingsStore.Save(settings);
            }

            if (args.PropertyName == nameof(SettingsState.SharedGroupId)
                || args.PropertyName == nameof(SettingsState.SharingEnabled))
            {
                syncService?.ScheduleDiscoveryRefresh();
            }
        };
        trayController = new TrayController(settings);
        syncService = new UdpTextSyncService(settings, new ClipPlusLogger(), Dispatcher);
        syncService.Start();

        if (ShouldOpenSettingsWindow(
            settings,
            Environment.GetEnvironmentVariable("CLIPPLUS_SHOW_SETTINGS_ON_START") == "1"))
        {
            trayController.ShowSettingsWindow();
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
        singleInstanceLock?.Dispose();
        base.OnExit(e);
    }
}
