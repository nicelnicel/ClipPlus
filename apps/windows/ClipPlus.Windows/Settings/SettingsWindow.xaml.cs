using System.Windows;
using System.ComponentModel;
using System.Diagnostics;
using System.Threading;
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
    private int sharedKeySaveGeneration;
    private DownloadedUpdate? pendingDownloadedUpdate;

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
        pendingDownloadedUpdate = null;
        InstallUpdateButton.Visibility = Visibility.Collapsed;
        SetUpdateStatus("正在检查更新...");
        try
        {
            var result = await updateService.CheckAndDownloadLatestAsync(progress =>
            {
                Dispatcher.Invoke(() =>
                {
                    var percent = (int)(progress * 100);
                    CheckUpdateButton.Content = $"下载中 {percent}%";
                    SetUpdateStatus($"正在下载更新 {percent}%");
                });
            });

            if (result.Status == UpdateCheckStatus.UpToDate)
            {
                SetUpdateStatus("已是最新版本");
                return;
            }

            var downloadedUpdate = result.DownloadedUpdate
                ?? throw new UpdateException(UpdateErrorKind.DownloadFailed);
            pendingDownloadedUpdate = downloadedUpdate;
            InstallUpdateButton.Visibility = Visibility.Visible;
            SetUpdateStatus($"新版本 v{downloadedUpdate.Version} 已下载完成");
        }
        catch (Exception error)
        {
            pendingDownloadedUpdate = null;
            InstallUpdateButton.Visibility = Visibility.Collapsed;
            SetUpdateStatus(error.Message, isError: true);
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

    private void InstallUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (pendingDownloadedUpdate is null)
        {
            return;
        }

        try
        {
            updateService.InstallAndRelaunch(pendingDownloadedUpdate);
        }
        catch (Exception error)
        {
            pendingDownloadedUpdate = null;
            InstallUpdateButton.Visibility = Visibility.Collapsed;
            SetUpdateStatus(error.Message, isError: true);
        }
    }

    private void SetUpdateStatus(string message, bool isError = false)
    {
        UpdateStatusText.Text = message;
        UpdateStatusText.Foreground = isError
            ? System.Windows.Media.Brushes.Firebrick
            : System.Windows.Media.Brushes.DimGray;
        UpdateStatusText.Visibility = string.IsNullOrWhiteSpace(message)
            ? Visibility.Collapsed
            : Visibility.Visible;
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
        var candidateKey = state.SharedKeyInput;
        if (string.IsNullOrWhiteSpace(candidateKey))
        {
            return;
        }

        var generation = Interlocked.Increment(ref sharedKeySaveGeneration);
        _ = Task.Run(() => SettingsState.PrepareSharedKeyUpdate(candidateKey, candidateKey))
            .ContinueWith(task =>
            {
                _ = Dispatcher.InvokeAsync(() =>
                {
                    if (generation != Volatile.Read(ref sharedKeySaveGeneration))
                    {
                        return;
                    }

                    if (task.IsFaulted)
                    {
                        var error = task.Exception?.GetBaseException() ?? new InvalidOperationException("共享 Key 保存失败");
                        System.Windows.MessageBox.Show(
                            this,
                            error.Message,
                            "ClipPlus",
                            MessageBoxButton.OK,
                            MessageBoxImage.Warning
                        );
                        return;
                    }

                    state.ApplySharedKeyUpdate(task.Result);
                    SyncPasswordBoxFromState();
                    UpdateSharedKeyPlaceholder();
                }, DispatcherPriority.Background);
            }, TaskScheduler.Default);
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
