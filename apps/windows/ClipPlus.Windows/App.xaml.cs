using System.Windows;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Tray;

namespace ClipPlus.Windows;

public partial class App : Application
{
    private TrayController? trayController;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var settings = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );
        trayController = new TrayController(settings);

        if (settings.RequiresKeySetup)
        {
            new SettingsWindow(settings).Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        trayController?.Dispose();
        base.OnExit(e);
    }
}
