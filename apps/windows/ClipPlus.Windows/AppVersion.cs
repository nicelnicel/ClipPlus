using System;

namespace ClipPlus.Windows;

public static class AppVersion
{
    public static string Current => FormatAssemblyVersion(typeof(AppVersion).Assembly.GetName().Version);

    public static string Display => $"v{Current}";

    public static string SettingsWindowTitle => $"ClipPlus {Display} 设置";

    public static string TrayText => $"ClipPlus {Display}";

    internal static string FormatAssemblyVersion(Version? version)
    {
        if (version is null)
        {
            return "dev";
        }

        if (version.Build >= 0)
        {
            return $"{version.Major}.{version.Minor}.{version.Build}";
        }

        return $"{version.Major}.{version.Minor}";
    }
}
