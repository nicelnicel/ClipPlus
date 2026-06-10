using System.IO;
using System.IO.Compression;
using System.Text.Json;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Diagnostics;

public sealed class DiagnosticsExporter
{
    private readonly string logPath;
    private readonly string destinationDirectory;
    private readonly IReadOnlyList<string> sensitiveValues;

    public DiagnosticsExporter()
        : this(ClipPlusLogger.DefaultLogPath, DefaultDestinationDirectory(), Array.Empty<string>())
    {
    }

    public DiagnosticsExporter(
        string logPath,
        string destinationDirectory,
        IReadOnlyList<string> sensitiveValues)
    {
        this.logPath = logPath;
        this.destinationDirectory = destinationDirectory;
        this.sensitiveValues = sensitiveValues;
    }

    public string Export(SettingsState state)
    {
        Directory.CreateDirectory(destinationDirectory);
        var exportPath = Path.Combine(
            destinationDirectory,
            $"ClipPlus-Diagnostics-{Timestamp()}.zip"
        );

        var status = new DiagnosticsStatus(
            ExportedAt: DateTimeOffset.UtcNow.ToString("O"),
            Platform: "Windows",
            SharedKeyConfigured: state.SharedKeyConfigured,
            SharingEnabled: state.SharingEnabled,
            StartupEnabled: state.StartupEnabled,
            PendingPeerCount: state.PendingPeerCount,
            TrustedPeerCount: state.TrustedPeerCount,
            LastStatusMessage: Redact(state.LastStatusMessage)
        );

        var json = JsonSerializer.Serialize(
            status,
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
                WriteIndented = true
            }
        );

        var log = File.Exists(logPath) ? File.ReadAllText(logPath) : string.Empty;
        if (File.Exists(exportPath))
        {
            File.Delete(exportPath);
        }

        using (var archive = ZipFile.Open(exportPath, ZipArchiveMode.Create))
        {
            WriteEntry(archive, "status.json", json);
            WriteEntry(archive, "clipplus.log", Redact(log));
        }

        return exportPath;
    }

    private string Redact(string value)
    {
        var redacted = value;
        foreach (var sensitiveValue in sensitiveValues
                     .Select(value => value.Trim())
                     .Where(value => !string.IsNullOrEmpty(value))
                     .OrderByDescending(value => value.Length))
        {
            redacted = redacted.Replace(sensitiveValue, "<redacted>", StringComparison.Ordinal);
        }

        return redacted;
    }

    private static string DefaultDestinationDirectory()
    {
        return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) is { Length: > 0 } userProfile
            ? Path.Combine(userProfile, "Downloads")
            : Path.GetTempPath();
    }

    private static string Timestamp()
    {
        return DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss-fff");
    }

    private static void WriteEntry(ZipArchive archive, string entryName, string contents)
    {
        var entry = archive.CreateEntry(entryName);
        using var writer = new StreamWriter(entry.Open());
        writer.Write(contents);
    }
}

internal sealed record DiagnosticsStatus(
    string ExportedAt,
    string Platform,
    bool SharedKeyConfigured,
    bool SharingEnabled,
    bool StartupEnabled,
    int PendingPeerCount,
    int TrustedPeerCount,
    string LastStatusMessage
);
