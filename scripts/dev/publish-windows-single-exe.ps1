param(
    [string]$RuntimeIdentifier = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$windowsDir = Join-Path $repoRoot "apps\windows"
$projectPath = Join-Path $windowsDir "ClipPlus.Windows\ClipPlus.Windows.csproj"
$outputDir = Join-Path $repoRoot "target\windows-single-exe"
$dotnet = "dotnet"

if ([string]::IsNullOrWhiteSpace($RuntimeIdentifier)) {
    $RuntimeIdentifier = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        "Arm64" { "win-arm64" }
        "X64" { "win-x64" }
        default { throw "Unsupported Windows architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" }
    }
}

$cargoTarget = switch ($RuntimeIdentifier) {
    "win-arm64" { "aarch64-pc-windows-msvc" }
    "win-x64" { "x86_64-pc-windows-msvc" }
    default { throw "Unsupported Windows runtime identifier: $RuntimeIdentifier" }
}

if (Test-Path "C:\dotnet\dotnet.exe") {
    $dotnet = "C:\dotnet\dotnet.exe"
}

Remove-Item -Recurse -Force $outputDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host "Publishing ClipPlus.Windows for $RuntimeIdentifier with Rust target $cargoTarget"

& $dotnet publish $projectPath `
    -c Release `
    -r $RuntimeIdentifier `
    --self-contained true `
    -o $outputDir `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:EnableCompressionInSingleFile=true `
    /p:ClipPlusCargoTarget=$cargoTarget `
    --nologo

$exePath = Join-Path $outputDir "ClipPlus.Windows.exe"
if (!(Test-Path $exePath)) {
    throw "Publish did not produce $exePath"
}

Get-Item $exePath | Select-Object FullName, Length
