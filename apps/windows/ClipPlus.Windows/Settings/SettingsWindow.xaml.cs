using System.Windows;

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
        catch (ArgumentException error)
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
}
