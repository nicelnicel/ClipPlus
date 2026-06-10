using System.IO;
using System.Windows;
using ClipPlus.Windows.Diagnostics;

namespace ClipPlus.Windows.Settings;

public partial class SettingsWindow : Window
{
    private readonly SettingsState state;

    public SettingsWindow(SettingsState state)
    {
        InitializeComponent();
        this.state = state;
        DataContext = state;
    }

    private void SaveKey_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            state.UpdateSharedKey(state.SharedKeyInput, state.SharedKeyConfirmationInput);
        }
        catch (Exception error)
        {
            System.Windows.MessageBox.Show(
                this,
                error.Message,
                "ClipPlus",
                MessageBoxButton.OK,
                MessageBoxImage.Warning
            );
        }
    }

    private void ApprovePendingPeers_Click(object sender, RoutedEventArgs e)
    {
        state.ApprovePendingPeers();
    }

    private void ApprovePendingPeer_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: string deviceId })
        {
            state.ApprovePendingPeer(deviceId);
        }
    }

    private void ReceiveRemoteFiles_Click(object sender, RoutedEventArgs e)
    {
        state.RequestRemoteFileReceive();
    }

    private void ExportDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        var sensitiveValues = new[]
        {
            Environment.GetEnvironmentVariable("CLIPPLUS_SHARED_KEY") ?? string.Empty
        };
        var exportDirectory = new DiagnosticsExporter(
            ClipPlusLogger.DefaultLogPath,
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            sensitiveValues
        ).Export(state);

        System.Windows.MessageBox.Show(
            this,
            $"已导出：{exportDirectory}",
            "ClipPlus",
            MessageBoxButton.OK,
            MessageBoxImage.Information
        );
    }
}
