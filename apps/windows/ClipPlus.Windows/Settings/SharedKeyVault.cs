using System.Diagnostics;
using System.IO;

namespace ClipPlus.Windows.Settings;

public interface SharedKeyVault
{
    string LoadSharedKey();
    void SaveSharedKey(string sharedKey);
}

public sealed class FileSharedKeyVault : SharedKeyVault
{
    public const string FileName = "clipplus.shared-key";

    private readonly string filePath;
    private readonly string? legacyFilePath;

    public FileSharedKeyVault()
        : this(DefaultFilePath(), LegacyProcessDirectoryFilePath())
    {
    }

    public FileSharedKeyVault(string filePath)
        : this(filePath, legacyFilePath: null)
    {
    }

    public FileSharedKeyVault(string filePath, string? legacyFilePath)
    {
        this.filePath = filePath;
        this.legacyFilePath = legacyFilePath;
    }

    public string LoadSharedKey()
    {
        var sharedKey = TryReadSharedKey(filePath);
        if (!string.IsNullOrEmpty(sharedKey))
        {
            return sharedKey;
        }

        if (string.IsNullOrWhiteSpace(legacyFilePath)
            || string.Equals(
                Path.GetFullPath(filePath),
                Path.GetFullPath(legacyFilePath),
                StringComparison.OrdinalIgnoreCase))
        {
            return string.Empty;
        }

        var legacySharedKey = TryReadSharedKey(legacyFilePath);
        if (string.IsNullOrEmpty(legacySharedKey))
        {
            return string.Empty;
        }

        TrySaveSharedKey(legacySharedKey);
        return legacySharedKey;
    }

    public void SaveSharedKey(string sharedKey)
    {
        TrySaveSharedKey(sharedKey, throwOnError: true);
    }

    private static string TryReadSharedKey(string path)
    {
        if (!File.Exists(path))
        {
            return string.Empty;
        }

        try
        {
            return File.ReadAllText(path).TrimEnd('\r', '\n');
        }
        catch (IOException)
        {
            return string.Empty;
        }
        catch (UnauthorizedAccessException)
        {
            return string.Empty;
        }
    }

    private void TrySaveSharedKey(string sharedKey, bool throwOnError = false)
    {
        try
        {
            var directory = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(filePath, sharedKey);
        }
        catch when (!throwOnError)
        {
        }
    }

    private static string DefaultFilePath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ClipPlus",
            FileName
        );
    }

    private static string? LegacyProcessDirectoryFilePath()
    {
        var processPath = Environment.ProcessPath
            ?? Process.GetCurrentProcess().MainModule?.FileName;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            var processDirectory = Path.GetDirectoryName(processPath);
            if (!string.IsNullOrWhiteSpace(processDirectory))
            {
                return Path.Combine(processDirectory, FileName);
            }
        }

        return null;
    }
}
