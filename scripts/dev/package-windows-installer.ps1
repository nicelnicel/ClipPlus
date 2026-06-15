param(
    [string]$FullExePath = "",
    [string]$OutputPath = "",
    [string]$RuntimeIdentifier = "win-x64"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$versionPath = Join-Path $repoRoot "VERSION"
$installerProject = Join-Path $repoRoot "apps\windows\ClipPlus.Installer\ClipPlus.Installer.csproj"
$defaultFullExePath = Join-Path $repoRoot "target\windows-release\ClipPlus-Windows-x64-full.exe"
$fallbackFullExePath = Join-Path $repoRoot "target\windows-single-exe\ClipPlus.Windows.exe"
$installerRoot = Join-Path $repoRoot "target\windows-installer"
$publishDir = Join-Path $installerRoot "publish"
$dotnetPath = "C:\dotnet\dotnet.exe"

if (!(Test-Path $dotnetPath)) {
    $dotnetCommand = Get-Command "dotnet" -ErrorAction SilentlyContinue
    if (!$dotnetCommand) {
        throw "dotnet SDK is required to build the Windows installer."
    }

    $dotnetPath = $dotnetCommand.Source
}

if ([string]::IsNullOrWhiteSpace($FullExePath)) {
    $FullExePath = $defaultFullExePath
}

if (!(Test-Path $FullExePath) -and (Test-Path $fallbackFullExePath)) {
    $FullExePath = $fallbackFullExePath
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $installerRoot "ClipPlus-Windows-x64-Setup.exe"
}

if (!(Test-Path $versionPath)) {
    throw "Missing VERSION file: $versionPath"
}

$version = (Get-Content -Raw $versionPath).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must be MAJOR.MINOR.PATCH, got: $version"
}

if (!(Test-Path $FullExePath)) {
    throw "Missing full Windows exe: $FullExePath"
}

if (!(Test-Path $installerProject)) {
    throw "Missing installer project: $installerProject"
}

Remove-Item -Recurse -Force $installerRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null

Push-Location $repoRoot
try {
    & $dotnetPath publish $installerProject `
        -c Release `
        -r $RuntimeIdentifier `
        --self-contained true `
        -o $publishDir `
        /p:ClipPlusPayloadPath="$FullExePath" `
        /p:Version="$version" `
        /p:AssemblyVersion="$version.0" `
        /p:FileVersion="$version.0" `
        /p:InformationalVersion="$version"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$publishedInstaller = Join-Path $publishDir "ClipPlus.Installer.exe"
if (!(Test-Path $publishedInstaller)) {
    throw "Installer publish did not produce: $publishedInstaller"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
Copy-Item -Force $publishedInstaller $OutputPath

if (!(Test-Path $OutputPath)) {
    throw "Installer was not produced: $OutputPath"
}

Get-Item $OutputPath | Select-Object FullName, Length
