namespace ClipPlus.Windows.Update;

using Microsoft.Win32;

public static class DotNetDesktopRuntimeDetector
{
    private static readonly string[] WindowsDesktopSharedFxKeyPaths =
    [
        @"SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
        @"SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
    ];

    public static bool HasDotNet8DesktopRuntime()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        return WindowsDesktopSharedFxKeyPaths.Any(HasDotNet8DesktopRuntime);
    }

    private static bool HasDotNet8DesktopRuntime(string keyPath)
    {
        using var key = Registry.LocalMachine.OpenSubKey(keyPath);
        return key?.GetValueNames().Any(name => name.StartsWith("8.", StringComparison.Ordinal)) == true;
    }
}
