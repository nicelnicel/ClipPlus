using System.Windows;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Navigation;
using System.Windows.Threading;
using ClipPlus.Windows.Update;

namespace ClipPlus.Windows.Settings;

public partial class SettingsWindow : Window
{
    private readonly SettingsState state;
    private readonly UpdateService updateService;
    private bool isSharedKeyVisible;
    private bool syncingPasswordBox;

    public SettingsWindow(SettingsState state)
        : this(state, new UpdateService())
    {
    }

    internal SettingsWindow(SettingsState state, UpdateService updateService)
    {
        InitializeComponent();
        Title = AppVersion.SettingsWindowTitle;
        this.state = state;
        this.updateService = updateService;
        DataContext = state;
        state.PropertyChanged += State_PropertyChanged;
        UpdateKeyInputMode();
        UpdateSharedKeyPlaceholder();
    }

    private void SharedKeyInput_LostFocus(object sender, RoutedEventArgs e)
    {
        Dispatcher.BeginInvoke(SaveAndHideSharedKeyIfFocusLeftInput, DispatcherPriority.Background);
    }

    private void ToggleKeyVisibility_Click(object sender, RoutedEventArgs e)
    {
        isSharedKeyVisible = !isSharedKeyVisible;
        UpdateKeyInputMode();
    }

    private void AuthorLink_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri)
        {
            UseShellExecute = true
        });
        e.Handled = true;
    }

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
        System.Windows.Application.Current.Shutdown();
    }

    private async void CheckUpdate_Click(object sender, RoutedEventArgs e)
    {
        CheckUpdateButton.IsEnabled = false;
        CheckUpdateButton.Content = "检查中...";
        try
        {
            var result = await updateService.CheckAndDownloadLatestAsync(progress =>
            {
                Dispatcher.Invoke(() =>
                {
                    CheckUpdateButton.Content = $"下载中 {(int)(progress * 100)}%";
                });
            });

            if (result.Status == UpdateCheckStatus.UpToDate)
            {
                System.Windows.MessageBox.Show(
                    this,
                    "已是最新版本",
                    "ClipPlus",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information
                );
                return;
            }

            var downloadedUpdate = result.DownloadedUpdate
                ?? throw new UpdateException(UpdateErrorKind.DownloadFailed);
            var response = System.Windows.MessageBox.Show(
                this,
                $"新版本 v{downloadedUpdate.Version} 已下载完成。ClipPlus 将退出并自动安装，然后重新启动。",
                "ClipPlus",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information
            );
            if (response == MessageBoxResult.Yes)
            {
                updateService.InstallAndRelaunch(downloadedUpdate);
            }
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
        finally
        {
            if (!Dispatcher.HasShutdownStarted)
            {
                CheckUpdateButton.Content = "检查更新";
                CheckUpdateButton.IsEnabled = true;
            }
        }
    }

    private void SharedKeyPasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (syncingPasswordBox)
        {
            return;
        }

        state.SharedKeyInput = SharedKeyPasswordBox.Password;
        UpdateSharedKeyPlaceholder();
    }

    private void State_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsState.SharedKeyInput))
        {
            if (!isSharedKeyVisible)
            {
                SyncPasswordBoxFromState();
            }

            UpdateSharedKeyPlaceholder();
        }

        if (e.PropertyName == nameof(SettingsState.RequiresKeySetup)
            || e.PropertyName == nameof(SettingsState.SharedKeyConfigured))
        {
            UpdateSharedKeyPlaceholder();
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        state.PropertyChanged -= State_PropertyChanged;
        base.OnClosed(e);
    }

    private void UpdateKeyInputMode()
    {
        var shouldUsePlainTextInput = isSharedKeyVisible || !state.SharedKeyConfigured;
        SharedKeyTextBox.Visibility = shouldUsePlainTextInput ? Visibility.Visible : Visibility.Collapsed;
        SharedKeyPasswordBox.Visibility = shouldUsePlainTextInput ? Visibility.Collapsed : Visibility.Visible;
        ToggleKeyVisibility.ToolTip = isSharedKeyVisible ? "隐藏共享 Key" : "查看共享 Key";
        ToggleKeyVisibilityIcon.Text = isSharedKeyVisible ? "\uE8F5" : "\uE890";

        if (shouldUsePlainTextInput)
        {
            if (!string.Equals(SharedKeyTextBox.Text, state.SharedKeyInput, StringComparison.Ordinal))
            {
                SharedKeyTextBox.Text = state.SharedKeyInput;
            }
        }
        else
        {
            SyncPasswordBoxFromState();
        }

        UpdateSharedKeyPlaceholder();
    }

    private void SaveAndHideSharedKeyIfFocusLeftInput()
    {
        if (IsFocusInsideSharedKeyInput())
        {
            return;
        }

        SaveSharedKeyIfNeeded();
        isSharedKeyVisible = false;
        UpdateKeyInputMode();
        Keyboard.ClearFocus();
    }

    private void SaveSharedKeyIfNeeded()
    {
        if (string.IsNullOrWhiteSpace(state.SharedKeyInput))
        {
            return;
        }

        try
        {
            state.UpdateSharedKey(state.SharedKeyInput, state.SharedKeyInput);
            SyncPasswordBoxFromState();
            UpdateSharedKeyPlaceholder();
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

    private void SyncPasswordBoxFromState()
    {
        if (string.Equals(SharedKeyPasswordBox.Password, state.SharedKeyInput, StringComparison.Ordinal))
        {
            return;
        }

        syncingPasswordBox = true;
        SharedKeyPasswordBox.Password = state.SharedKeyInput;
        syncingPasswordBox = false;
    }

    private void UpdateSharedKeyPlaceholder()
    {
        SharedKeyPlaceholderText.Visibility = string.IsNullOrEmpty(state.SharedKeyInput)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private bool IsFocusInsideSharedKeyInput()
    {
        if (Keyboard.FocusedElement is not DependencyObject focusedElement)
        {
            return false;
        }

        return IsDescendantOf(focusedElement, SharedKeyInputContainer)
            || ReferenceEquals(focusedElement, ToggleKeyVisibility);
    }

    private static bool IsDescendantOf(DependencyObject child, DependencyObject ancestor)
    {
        var current = child;
        while (current is not null)
        {
            if (ReferenceEquals(current, ancestor))
            {
                return true;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return false;
    }
}
