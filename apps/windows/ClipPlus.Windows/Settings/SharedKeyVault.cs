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

    public FileSharedKeyVault()
        : this(DefaultFilePath())
    {
    }

    public FileSharedKeyVault(string filePath)
    {
        this.filePath = filePath;
    }

    public string LoadSharedKey()
    {
        if (!File.Exists(filePath))
        {
            return string.Empty;
        }

        try
        {
            return File.ReadAllText(filePath).TrimEnd('\r', '\n');
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

    public void SaveSharedKey(string sharedKey)
    {
        var directory = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(filePath, sharedKey);
    }

    private static string DefaultFilePath()
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

        return Path.Combine(AppContext.BaseDirectory, FileName);
    }
}
