namespace ClipPlus.Windows.Settings;

public sealed class SettingsState
{
    public SettingsState(bool sharedKeyConfigured, bool sharingEnabled, bool startupEnabled)
    {
        SharedKeyConfigured = sharedKeyConfigured;
        SharingEnabled = sharingEnabled;
        StartupEnabled = startupEnabled;
    }

    public bool SharedKeyConfigured { get; set; }
    public bool SharingEnabled { get; set; }
    public bool StartupEnabled { get; set; }
    public bool RequiresKeySetup => !SharedKeyConfigured;
}
