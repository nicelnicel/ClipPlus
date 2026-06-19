namespace ClipPlus.Windows.Update;

using Microsoft.Win32;

public static class DotNetDesktopRuntimeDetector
{
    private const string WindowsDesktopSharedFxKeyPath =
        @"SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App";

    public static bool HasDotNet8DesktopRuntime()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        using var key = Registry.LocalMachine.OpenSubKey(WindowsDesktopSharedFxKeyPath);
        return key?.GetValueNames().Any(name => name.StartsWith("8.", StringComparison.Ordinal)) == true;
    }
}
