namespace ClipPlus.Windows.Sync;

using System.Security.Cryptography;

public static class ImageContentHasher
{
    public static string Sha256Hex(byte[] data)
    {
        return Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();
    }
}
