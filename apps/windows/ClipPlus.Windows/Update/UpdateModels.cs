namespace ClipPlus.Windows.Update;

using System.IO;

public enum UpdateErrorKind
{
    InvalidVersion,
    UpToDate,
    MissingAsset,
    MissingDigest,
    InvalidDigest,
    Sha256Mismatch,
    UnsupportedRuntime,
    DownloadFailed
}

public enum WindowsUpdatePackageKind
{
    Full,
    RuntimeDependent,
    Installed
}

public static class WindowsUpdatePackageKindDetector
{
    public const string PackageMarkerFileName = "clipplus-package.json";
    public const string InstalledRuntimeDependentMarker = "installed-runtime-dependent";

    public static WindowsUpdatePackageKind DetectCurrent()
    {
        return DetectFromExecutablePath(Environment.ProcessPath);
    }

    public static WindowsUpdatePackageKind DetectFromExecutablePath(string? executablePath)
    {
        var fileName = string.IsNullOrWhiteSpace(executablePath)
            ? string.Empty
            : Path.GetFileName(executablePath);
        if (fileName.Contains("runtime-dependent", StringComparison.OrdinalIgnoreCase))
        {
            return WindowsUpdatePackageKind.RuntimeDependent;
        }

        return HasInstalledMarker(Path.GetDirectoryName(executablePath)) || IsCurrentUserInstallPath(executablePath)
            ? WindowsUpdatePackageKind.Installed
            : WindowsUpdatePackageKind.Full;
    }

    private static bool HasInstalledMarker(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory))
        {
            return false;
        }

        var markerPath = Path.Combine(directory, PackageMarkerFileName);
        try
        {
            return File.Exists(markerPath)
                && File.ReadAllText(markerPath).Contains(InstalledRuntimeDependentMarker, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsCurrentUserInstallPath(string? executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return false;
        }

        try
        {
            var expectedPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs",
                "ClipPlus",
                "ClipPlus.exe"
            );
            return Path.GetFullPath(executablePath).Equals(
                Path.GetFullPath(expectedPath),
                StringComparison.OrdinalIgnoreCase
            );
        }
        catch
        {
            return false;
        }
    }
}

public sealed class UpdateException : Exception
{
    public UpdateException(UpdateErrorKind kind)
        : base(MessageFor(kind))
    {
        Kind = kind;
    }

    public UpdateErrorKind Kind { get; }

    private static string MessageFor(UpdateErrorKind kind)
    {
        return kind switch
        {
            UpdateErrorKind.InvalidVersion => "更新版本格式无效",
            UpdateErrorKind.UpToDate => "已是最新版本",
            UpdateErrorKind.MissingAsset => "当前平台没有可用更新包",
            UpdateErrorKind.MissingDigest => "更新包缺少校验信息",
            UpdateErrorKind.InvalidDigest => "更新包校验信息无效",
            UpdateErrorKind.Sha256Mismatch => "更新包校验失败",
            UpdateErrorKind.UnsupportedRuntime => "缺少 .NET 8 Desktop Runtime，Windows 普通版无法自动更新",
            UpdateErrorKind.DownloadFailed => "更新包下载失败",
            _ => "更新失败"
        };
    }
}

public readonly record struct UpdateVersion(int Major, int Minor, int Patch) : IComparable<UpdateVersion>
{
    public static UpdateVersion Parse(string value)
    {
        return TryParse(value, out var version)
            ? version
            : throw new UpdateException(UpdateErrorKind.InvalidVersion);
    }

    public static bool TryParse(string value, out UpdateVersion version)
    {
        version = default;
        var normalized = value.Trim();
        if (normalized.StartsWith("v", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized[1..];
        }

        var parts = normalized.Split('.');
        if (parts.Length != 3
            || !int.TryParse(parts[0], out var major)
            || !int.TryParse(parts[1], out var minor)
            || !int.TryParse(parts[2], out var patch))
        {
            return false;
        }

        version = new UpdateVersion(major, minor, patch);
        return true;
    }

    public int CompareTo(UpdateVersion other)
    {
        var major = Major.CompareTo(other.Major);
        if (major != 0)
        {
            return major;
        }

        var minor = Minor.CompareTo(other.Minor);
        return minor != 0 ? minor : Patch.CompareTo(other.Patch);
    }

    public override string ToString()
    {
        return $"{Major}.{Minor}.{Patch}";
    }
}

public sealed record SelectedUpdateAsset(
    UpdateVersion Version,
    string Name,
    Uri DownloadUrl,
    string Sha256Hex,
    long Size
);

public sealed record DownloadedUpdate(
    UpdateVersion Version,
    string AssetName,
    string FilePath
);

public enum UpdateCheckStatus
{
    UpToDate,
    Downloaded
}

public sealed record UpdateCheckResult(
    UpdateCheckStatus Status,
    DownloadedUpdate? DownloadedUpdate
)
{
    public static UpdateCheckResult UpToDate() => new(UpdateCheckStatus.UpToDate, null);

    public static UpdateCheckResult Downloaded(DownloadedUpdate update) => new(UpdateCheckStatus.Downloaded, update);
}
