using System.IO;
using System.IO.Compression;

namespace ClipPlus.Windows.Sync;

public static class FileTransferArchive
{
    public static void WriteZip(IReadOnlyList<string> sourcePaths, string archivePath)
    {
        if (File.Exists(archivePath))
        {
            File.Delete(archivePath);
        }

        using var archive = ZipFile.Open(archivePath, ZipArchiveMode.Create);
        foreach (var sourcePath in sourcePaths)
        {
            if (File.Exists(sourcePath))
            {
                archive.CreateEntryFromFile(sourcePath, Path.GetFileName(sourcePath));
                continue;
            }

            if (Directory.Exists(sourcePath))
            {
                AddDirectory(archive, sourcePath);
            }
        }
    }

    private static void AddDirectory(ZipArchive archive, string directoryPath)
    {
        var parentPath = Directory.GetParent(directoryPath)?.FullName ?? directoryPath;
        foreach (var filePath in Directory.EnumerateFiles(directoryPath, "*", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(parentPath, filePath).Replace('\\', '/');
            archive.CreateEntryFromFile(filePath, relativePath);
        }
    }
}
