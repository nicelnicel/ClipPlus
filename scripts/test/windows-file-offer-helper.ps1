param(
    [Parameter(Mandatory = $true)]
    [string] $Marker,

    [Parameter(Mandatory = $true)]
    [string] $TransferId,

    [Parameter(Mandatory = $true)]
    [string] $TargetHost,

    [string] $GroupId = "21YR2N3_wcdRPmEMLiuLMA",
    [int] $UdpPort = 47631,
    [int] $ArchivePort = 47632,
    [int] $WaitSeconds = 180,
    [switch] $SkipClipboard
)

$ErrorActionPreference = "Stop"

$deviceIdPath = Join-Path $env:LOCALAPPDATA "ClipPlus/device.id"
$deviceId = (Get-Content $deviceIdPath -Raw).Trim()
$directory = Join-Path $env:TEMP "ClipPlusE2E"
New-Item -ItemType Directory -Force -Path $directory | Out-Null

$sourcePath = Join-Path $directory "windows-rust-download-source.txt"
Set-Content -Path $sourcePath -Value $Marker -NoNewline
if (-not $SkipClipboard) {
    Set-Clipboard -Path $sourcePath
}

$zipPath = Join-Path $directory "$TransferId.zip"
Remove-Item $zipPath -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
    $zipPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        $sourcePath,
        [IO.Path]::GetFileName($sourcePath)
    ) | Out-Null
} finally {
    $archive.Dispose()
}

$zipBytes = [IO.File]::ReadAllBytes($zipPath)
$sourceItem = Get-Item $sourcePath
$message = [ordered]@{
    kind = "fileOffer"
    protocolVersion = 1
    groupId = $GroupId
    senderDeviceId = $deviceId
    senderDeviceName = $env:COMPUTERNAME
    eventId = [guid]::NewGuid().ToString()
    transferId = $TransferId
    files = @(
        [ordered]@{
            relativePath = $sourceItem.Name
            byteSize = $sourceItem.Length
            isDirectory = $false
        }
    )
    archivePort = $ArchivePort
    createdAt = [DateTimeOffset]::UtcNow.ToString("O")
}

$json = $message | ConvertTo-Json -Depth 6 -Compress
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $ArchivePort)
$listener.Start()
try {
    Write-Output "HelperListening transferId=$TransferId marker=$Marker zipBytes=$($zipBytes.Length) sourcePath=$sourcePath"

    $udp = [Net.Sockets.UdpClient]::new()
    try {
        $payload = [Text.Encoding]::UTF8.GetBytes($json)
        1..5 | ForEach-Object {
            [void] $udp.Send($payload, $payload.Length, $TargetHost, $UdpPort)
            Start-Sleep -Milliseconds 500
        }
    } finally {
        $udp.Dispose()
    }
    Write-Output "OfferSent target=$TargetHost udpPort=$UdpPort"

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($WaitSeconds)
    while (-not $listener.Pending()) {
        if ([DateTimeOffset]::UtcNow -gt $deadline) {
            throw "Timed out waiting for archive download"
        }
        Start-Sleep -Milliseconds 200
    }

    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 1024, $true)
        $requestedTransferId = $reader.ReadLine()
        Write-Output "RequestedTransferId=$requestedTransferId"
        if ($requestedTransferId -ne $TransferId) {
            throw "Unexpected transfer id $requestedTransferId"
        }

        $length = [BitConverter]::GetBytes([UInt64] $zipBytes.Length)
        if ([BitConverter]::IsLittleEndian) {
            [Array]::Reverse($length)
        }
        $stream.Write($length, 0, $length.Length)
        $stream.Write($zipBytes, 0, $zipBytes.Length)
        $stream.Flush()
        Write-Output "served file archive file_count=1 byte_count=$($zipBytes.Length)"
    } finally {
        $client.Dispose()
    }
} finally {
    $listener.Stop()
}
