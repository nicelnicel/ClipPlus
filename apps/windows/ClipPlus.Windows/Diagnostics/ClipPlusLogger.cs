using System.IO;

namespace ClipPlus.Windows.Diagnostics;

public sealed class ClipPlusLogger
{
    private readonly string logPath;
    private readonly object gate = new();

    public ClipPlusLogger()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ClipPlus",
            "logs"
        );
        Directory.CreateDirectory(directory);
        logPath = Path.Combine(directory, "clipplus.log");
    }

    public void Info(string message)
    {
        Write("info", message);
    }

    public void Error(string message)
    {
        Write("error", message);
    }

    private void Write(string level, string message)
    {
        var line = $"{DateTimeOffset.UtcNow:O} [{level}] {message}{Environment.NewLine}";
        lock (gate)
        {
            File.AppendAllText(logPath, line);
        }
    }
}
