using System.Windows;

namespace ClipPlus.Windows.Settings;

public partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsState state)
    {
        InitializeComponent();
        DataContext = state;
    }
}
