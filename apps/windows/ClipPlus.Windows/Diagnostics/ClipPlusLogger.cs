using System.IO;

namespace ClipPlus.Windows.Diagnostics;

public sealed class ClipPlusLogger
{
    public static string DefaultLogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ClipPlus",
        "logs",
        "clipplus.log"
    );

    private readonly string logPath;
    private readonly object gate = new();

    public ClipPlusLogger()
    {
        var directory = Path.GetDirectoryName(DefaultLogPath)
            ?? throw new InvalidOperationException("无法定位 ClipPlus 日志目录");
        Directory.CreateDirectory(directory);
        logPath = DefaultLogPath;
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
