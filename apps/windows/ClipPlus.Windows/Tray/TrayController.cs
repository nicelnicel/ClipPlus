using System;
using System.Drawing;
using System.Windows.Forms;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Tray;

public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon notifyIcon;
    private readonly SettingsState settingsState;

    public TrayController(SettingsState settingsState)
    {
        this.settingsState = settingsState;
        notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "ClipPlus",
            Visible = true
        };
        notifyIcon.ContextMenuStrip = BuildMenu();
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(settingsState.RequiresKeySetup ? "状态：共享 Key 未设置" : "状态：准备就绪");
        menu.Items.Add("打开设置...", null, (_, _) => new SettingsWindow(settingsState).Show());
        menu.Items.Add("退出 ClipPlus", null, (_, _) => System.Windows.Application.Current.Shutdown());
        return menu;
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
    }
}
