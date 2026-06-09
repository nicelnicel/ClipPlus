namespace ClipPlus.Windows.Startup;

public sealed class StartupManager
{
    public bool IsEnabled()
    {
        return false;
    }

    public void SetEnabled(bool enabled)
    {
        _ = enabled;
    }
}
