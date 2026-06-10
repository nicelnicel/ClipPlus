using System.IO;
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
        var exportDirectory = Path.Combine(
            destinationDirectory,
            $"ClipPlus-Diagnostics-{Timestamp()}"
        );
        Directory.CreateDirectory(exportDirectory);

        var status = new DiagnosticsStatus(
            ExportedAt: DateTimeOffset.UtcNow.ToString("O"),
            Platform: "Windows",
            SharedKeyConfigured: state.SharedKeyConfigured,
            SharingEnabled: state.SharingEnabled,
            StartupEnabled: state.StartupEnabled,
            PendingPeerCount: state.PendingPeerCount,
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
        File.WriteAllText(Path.Combine(exportDirectory, "status.json"), json);

        var log = File.Exists(logPath) ? File.ReadAllText(logPath) : string.Empty;
        File.WriteAllText(Path.Combine(exportDirectory, "clipplus.log"), Redact(log));

        return exportDirectory;
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
        return DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss");
    }
}

internal sealed record DiagnosticsStatus(
    string ExportedAt,
    string Platform,
    bool SharedKeyConfigured,
    bool SharingEnabled,
    bool StartupEnabled,
    int PendingPeerCount,
    string LastStatusMessage
);
