namespace ClipPlus.Windows.Sync;

public static class FileTransferArchive
{
    public static void WriteZip(IReadOnlyList<string> sourcePaths, string archivePath)
    {
        var written = new ClipPlus.Windows.CoreBridge.CoreBridge()
            .WriteFileArchiveZip(sourcePaths, archivePath);
        if (!written)
        {
            throw new InvalidOperationException("Rust core library is unavailable; cannot create file transfer archive.");
        }
    }
}
