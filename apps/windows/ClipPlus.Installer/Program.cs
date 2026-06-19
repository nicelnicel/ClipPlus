using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

internal static class Program
{
    private const string AppName = "ClipPlus";
    private const string PayloadResourceName = "ClipPlus.exe";
    private const string InstalledExeName = "ClipPlus.exe";
    private const string PackageMarkerFileName = "clipplus-package.json";
    private const string InstalledRuntimeDependentMarker = "installed-runtime-dependent";
    private const string UninstallScriptName = "Uninstall.cmd";
    private const string UninstallPowerShellScriptName = "Uninstall.ps1";
    private const string ShortcutName = "ClipPlus.lnk";
    private const string RunValueName = "ClipPlus";
    private const string UninstallKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipPlus";
    private const string WindowsDesktopSharedFxKeyPath =
        @"SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App";
    private const uint MessageBoxIconError = 0x00000010;

    private static int Main(string[] args)
    {
        try
        {
            if (args.Any(IsUninstallArgument))
            {
                Uninstall();
                return 0;
            }

            Install();
            return 0;
        }
        catch (Exception exception)
        {
            try
            {
                File.WriteAllText(
                    Path.Combine(Path.GetTempPath(), "ClipPlus-Setup-Error.txt"),
                    exception.ToString()
                );
            }
            catch
            {
                // Best-effort diagnostic only.
            }

            TryShowError(exception.Message);
            return 1;
        }
    }

    private static bool IsUninstallArgument(string value)
    {
        return string.Equals(value, "/uninstall", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "--uninstall", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "uninstall", StringComparison.OrdinalIgnoreCase);
    }

    private static void Install()
    {
        var installDirectory = InstallDirectory();
        var installedExePath = Path.Combine(installDirectory, InstalledExeName);
        var uninstallScriptPath = Path.Combine(installDirectory, UninstallScriptName);
        var uninstallPowerShellScriptPath = Path.Combine(installDirectory, UninstallPowerShellScriptName);

        EnsureDotNet8DesktopRuntime();
        Directory.CreateDirectory(installDirectory);
        StopClipPlusProcesses();

        using (var payloadStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName))
        {
            if (payloadStream is null)
            {
                throw new InvalidOperationException("Missing embedded ClipPlus payload.");
            }

            using var output = File.Create(installedExePath);
            payloadStream.CopyTo(output);
        }

        WriteUninstallScripts(uninstallScriptPath, uninstallPowerShellScriptPath);
        WritePackageMarker(installDirectory);
        CreateShortcut(installedExePath);
        WriteUninstallRegistry(installedExePath, uninstallPowerShellScriptPath);

        Process.Start(new ProcessStartInfo
        {
            FileName = installedExePath,
            WorkingDirectory = installDirectory,
            UseShellExecute = true,
        });
    }

    private static void Uninstall()
    {
        StopClipPlusProcesses();

        Registry.CurrentUser
            .OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true)
            ?.DeleteValue(RunValueName, throwOnMissingValue: false);
        Registry.CurrentUser.DeleteSubKeyTree(UninstallKeyPath, throwOnMissingSubKey: false);

        var shortcutPath = ShortcutPath();
        if (File.Exists(shortcutPath))
        {
            File.Delete(shortcutPath);
        }

        var installDirectory = InstallDirectory();
        if (Directory.Exists(installDirectory))
        {
            Directory.Delete(installDirectory, recursive: true);
        }
    }

    private static void StopClipPlusProcesses()
    {
        var currentProcessId = Environment.ProcessId;
        var names = new[]
        {
            "ClipPlus",
            "ClipPlus.Windows",
            "ClipPlus-Windows-x64-full",
            "ClipPlus-Windows-x64-runtime-dependent",
        };

        foreach (var name in names)
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                using (process)
                {
                    if (process.Id == currentProcessId)
                    {
                        continue;
                    }

                    try
                    {
                        process.Kill(entireProcessTree: true);
                        process.WaitForExit(5000);
                    }
                    catch
                    {
                        // Installation should continue even when a stale process exits first.
                    }
                }
            }
        }
    }

    private static void WriteUninstallScripts(string commandScriptPath, string powerShellScriptPath)
    {
        var installDirectory = InstallDirectory();
        var commandScript = """
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
endlocal
exit /b %EXIT_CODE%
""";

        var powerShellScript = """
param(
    [switch]$RunFromTemp
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $RunFromTemp) {
    $tempScript = Join-Path $env:TEMP ("ClipPlus-Uninstall-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    Copy-Item -Force $PSCommandPath $tempScript
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript -RunFromTemp
    $exitCode = $LASTEXITCODE
    Remove-Item -Force $tempScript -ErrorAction SilentlyContinue
    exit $exitCode
}

Get-Process ClipPlus,ClipPlus.Windows,"ClipPlus-Windows-x64-full","ClipPlus-Windows-x64-runtime-dependent" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ClipPlus" -ErrorAction SilentlyContinue
Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipPlus" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ClipPlus.lnk") -Force -ErrorAction SilentlyContinue

$installDirectory = "__INSTALL_DIR__"
for ($i = 0; $i -lt 20; $i++) {
    Remove-Item $installDirectory -Recurse -Force -ErrorAction SilentlyContinue
    if (!(Test-Path $installDirectory)) {
        exit 0
    }
    Start-Sleep -Milliseconds 500
}

exit 1
""".Replace("__INSTALL_DIR__", EscapePowerShellString(installDirectory), StringComparison.Ordinal);

        File.WriteAllText(commandScriptPath, commandScript);
        File.WriteAllText(powerShellScriptPath, powerShellScript);
    }

    private static void WritePackageMarker(string installDirectory)
    {
        var marker = $$"""
{
  "package_kind": "{{InstalledRuntimeDependentMarker}}"
}
""";
        File.WriteAllText(Path.Combine(installDirectory, PackageMarkerFileName), marker);
    }

    private static void EnsureDotNet8DesktopRuntime()
    {
        if (!HasDotNet8DesktopRuntime())
        {
            throw new InvalidOperationException(
                "ClipPlus 需要先安装 .NET 8 Desktop Runtime；也可以下载 ClipPlus-Windows-x64-full.exe。"
            );
        }
    }

    private static bool HasDotNet8DesktopRuntime()
    {
        using var key = Registry.LocalMachine.OpenSubKey(WindowsDesktopSharedFxKeyPath);
        return key?.GetValueNames().Any(name => name.StartsWith("8.", StringComparison.Ordinal)) == true;
    }

    private static void CreateShortcut(string installedExePath)
    {
        var shortcutPath = ShortcutPath();
        var command = string.Join(
            "; ",
            "$shell = New-Object -ComObject WScript.Shell",
            "$shortcut = $shell.CreateShortcut($env:APPDATA + '\\Microsoft\\Windows\\Start Menu\\Programs\\ClipPlus.lnk')",
            "$shortcut.TargetPath = $env:LOCALAPPDATA + '\\Programs\\ClipPlus\\ClipPlus.exe'",
            "$shortcut.WorkingDirectory = $env:LOCALAPPDATA + '\\Programs\\ClipPlus'",
            "$shortcut.IconLocation = $shortcut.TargetPath",
            "$shortcut.Save()"
        );

        RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"");

        if (!File.Exists(shortcutPath))
        {
            throw new InvalidOperationException("Failed to create ClipPlus start menu shortcut.");
        }
    }

    private static void WriteUninstallRegistry(string installedExePath, string uninstallPowerShellScriptPath)
    {
        using var key = Registry.CurrentUser.CreateSubKey(UninstallKeyPath);
        if (key is null)
        {
            throw new InvalidOperationException("Failed to create ClipPlus uninstall registry key.");
        }

        key.SetValue("DisplayName", AppName, RegistryValueKind.String);
        key.SetValue("DisplayVersion", Version(), RegistryValueKind.String);
        key.SetValue("Publisher", "YJY", RegistryValueKind.String);
        key.SetValue("InstallLocation", InstallDirectory(), RegistryValueKind.String);
        key.SetValue("DisplayIcon", Quote(installedExePath), RegistryValueKind.String);
        key.SetValue("UninstallString", PowerShellUninstallCommand(uninstallPowerShellScriptPath), RegistryValueKind.String);
        key.SetValue("QuietUninstallString", PowerShellUninstallCommand(uninstallPowerShellScriptPath), RegistryValueKind.String);
    }

    private static void RunHidden(string fileName, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        });

        if (process is null)
        {
            throw new InvalidOperationException($"Failed to start {fileName}.");
        }

        if (!process.WaitForExit(15000))
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException($"{fileName} timed out.");
        }

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"{fileName} exited with code {process.ExitCode}.");
        }
    }

    private static string InstallDirectory()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            "ClipPlus"
        );
    }

    private static string ShortcutPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Microsoft",
            "Windows",
            "Start Menu",
            "Programs",
            ShortcutName
        );
    }

    private static string Version()
    {
        return typeof(Program)
            .Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            ?? "0.0.0";
    }

    private static string Quote(string value)
    {
        return "\"" + value + "\"";
    }

    private static string PowerShellUninstallCommand(string scriptPath)
    {
        return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " + Quote(scriptPath);
    }

    private static string EscapePowerShellString(string value)
    {
        return value.Replace("`", "``", StringComparison.Ordinal).Replace("\"", "`\"", StringComparison.Ordinal);
    }

    private static void TryShowError(string message)
    {
        try
        {
            _ = MessageBoxW(IntPtr.Zero, message, "ClipPlus Setup", MessageBoxIconError);
        }
        catch
        {
            // Error reporting must not mask the original installer failure.
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}
