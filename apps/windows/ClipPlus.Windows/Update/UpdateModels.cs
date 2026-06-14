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
    RuntimeDependent
}

public static class WindowsUpdatePackageKindDetector
{
    public static WindowsUpdatePackageKind DetectCurrent()
    {
        return DetectFromExecutablePath(Environment.ProcessPath);
    }

    public static WindowsUpdatePackageKind DetectFromExecutablePath(string? executablePath)
    {
        var fileName = string.IsNullOrWhiteSpace(executablePath)
            ? string.Empty
            : Path.GetFileName(executablePath);
        return fileName.Contains("runtime-dependent", StringComparison.OrdinalIgnoreCase)
            ? WindowsUpdatePackageKind.RuntimeDependent
            : WindowsUpdatePackageKind.Full;
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
            UpdateErrorKind.UnsupportedRuntime => "当前运行方式不支持自动更新",
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
