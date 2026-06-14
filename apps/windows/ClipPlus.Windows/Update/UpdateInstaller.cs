namespace ClipPlus.Windows.Update;

using System.Diagnostics;
using System.IO;
using System.Windows;

public sealed class WindowsUpdateInstaller
{
    public static string CreateUpdaterScript(
        string currentExePath,
        string newExePath,
        int currentProcessId)
    {
        var backupExePath = $"{currentExePath}.old";
        return $$"""
        $ErrorActionPreference = "Stop"
        $currentExe = '{{EscapePowerShellSingleQuoted(currentExePath)}}'
        $newExe = '{{EscapePowerShellSingleQuoted(newExePath)}}'
        $backupExe = '{{EscapePowerShellSingleQuoted(backupExePath)}}'

        Wait-Process -Id {{currentProcessId}} -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300

        if (Test-Path -LiteralPath $backupExe) {
          Remove-Item -LiteralPath $backupExe -Force
        }

        Move-Item -LiteralPath $currentExe -Destination $backupExe
        try {
          Copy-Item -LiteralPath $newExe -Destination $currentExe
          Start-Process -FilePath $currentExe
          Start-Sleep -Seconds 2
          Remove-Item -LiteralPath $backupExe -Force -ErrorAction SilentlyContinue
        } catch {
          if (Test-Path -LiteralPath $backupExe) {
            Copy-Item -LiteralPath $backupExe -Destination $currentExe -Force
          }
          throw
        }
        """;
    }

    public void InstallAndRelaunch(DownloadedUpdate downloadedUpdate)
    {
        var currentExePath = Environment.ProcessPath
            ?? Process.GetCurrentProcess().MainModule?.FileName
            ?? string.Empty;
        if (string.IsNullOrWhiteSpace(currentExePath)
            || string.Equals(Path.GetFileName(currentExePath), "dotnet.exe", StringComparison.OrdinalIgnoreCase)
            || !File.Exists(currentExePath))
        {
            throw new UpdateException(UpdateErrorKind.UnsupportedRuntime);
        }

        var scriptPath = Path.Combine(Path.GetTempPath(), $"clipplus-windows-update-{Guid.NewGuid():N}.ps1");
        File.WriteAllText(
            scriptPath,
            CreateUpdaterScript(currentExePath, downloadedUpdate.FilePath, Environment.ProcessId)
        );

        Process.Start(new ProcessStartInfo
        {
            FileName = "powershell",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
        Application.Current.Shutdown();
    }

    private static string EscapePowerShellSingleQuoted(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
    }
}
