using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Tray;

public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon notifyIcon;
    private readonly SettingsState settingsState;
    private readonly Icon icon;
    private SettingsWindow? settingsWindow;

    public TrayController(SettingsState settingsState)
    {
        this.settingsState = settingsState;
        icon = LoadApplicationIcon();
        notifyIcon = new NotifyIcon
        {
            Icon = icon,
            Text = AppVersion.TrayText,
            Visible = true
        };
        notifyIcon.ContextMenuStrip = BuildMenu();
        notifyIcon.MouseClick += (_, args) =>
        {
            if (args.Button == MouseButtons.Left)
            {
                ShowSettingsWindow();
            }
        };
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开设置...", null, (_, _) => ShowSettingsWindow());
        menu.Items.Add("退出 ClipPlus", null, (_, _) => System.Windows.Application.Current.Shutdown());
        return menu;
    }

    public void ShowSettingsWindow()
    {
        System.Windows.Application.Current.Dispatcher.Invoke(ShowSettingsWindowOnUiThread);
    }

    private void ShowSettingsWindowOnUiThread()
    {
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(settingsState);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
            settingsWindow.Show();
            return;
        }

        if (settingsWindow.WindowState == System.Windows.WindowState.Minimized)
        {
            settingsWindow.WindowState = System.Windows.WindowState.Normal;
        }

        settingsWindow.Show();
        settingsWindow.Activate();
    }

    public void Dispose()
    {
        settingsWindow?.Close();
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        icon.Dispose();
    }

    private static Icon LoadApplicationIcon()
    {
        var executablePath = Process.GetCurrentProcess().MainModule?.FileName;
        if (!string.IsNullOrWhiteSpace(executablePath))
        {
            return Icon.ExtractAssociatedIcon(executablePath) ?? (Icon)SystemIcons.Application.Clone();
        }

        return (Icon)SystemIcons.Application.Clone();
    }
}
