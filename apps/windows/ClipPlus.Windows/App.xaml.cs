using System.Windows;
using ClipPlus.Windows.Diagnostics;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Sync;
using ClipPlus.Windows.Tray;

namespace ClipPlus.Windows;

public partial class App : System.Windows.Application
{
    private TrayController? trayController;
    private UdpTextSyncService? syncService;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var settings = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );
        trayController = new TrayController(settings);
        syncService = new UdpTextSyncService(settings, new ClipPlusLogger(), Dispatcher);
        syncService.Start();

        if (settings.RequiresKeySetup)
        {
            new SettingsWindow(settings).Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        syncService?.Dispose();
        trayController?.Dispose();
        base.OnExit(e);
    }
}
