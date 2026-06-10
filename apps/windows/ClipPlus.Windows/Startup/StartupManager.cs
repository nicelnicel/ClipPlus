using Microsoft.Win32;

namespace ClipPlus.Windows.Startup;

public sealed class StartupManager
{
    private const string EntryName = "ClipPlus";
    private readonly IStartupEntryStore store;
    private readonly string executablePath;

    public StartupManager()
        : this(new RegistryStartupEntryStore(), Environment.ProcessPath ?? string.Empty)
    {
    }

    public StartupManager(IStartupEntryStore store, string executablePath)
    {
        this.store = store;
        this.executablePath = executablePath;
    }

    public bool IsEnabled()
    {
        var currentValue = store.ReadValue(EntryName);
        return string.Equals(currentValue, FormatRunValue(executablePath), StringComparison.OrdinalIgnoreCase);
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled)
        {
            store.SetValue(EntryName, FormatRunValue(executablePath));
        }
        else
        {
            store.DeleteValue(EntryName);
        }
    }

    private static string FormatRunValue(string path)
    {
        return $"\"{path}\"";
    }
}

public interface IStartupEntryStore
{
    string? ReadValue(string name);
    void SetValue(string name, string value);
    void DeleteValue(string name);
}

public sealed class RegistryStartupEntryStore : IStartupEntryStore
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public string? ReadValue(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(name) as string;
    }

    public void SetValue(string name, string value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true)
            ?? throw new InvalidOperationException("无法打开 Windows 启动项注册表");
        key.SetValue(name, value, RegistryValueKind.String);
    }

    public void DeleteValue(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
        key?.DeleteValue(name, throwOnMissingValue: false);
    }
}
