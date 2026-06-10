using System.Security.Cryptography;
using System.Text;

namespace ClipPlus.Windows.Sync;

public static class SharedKeyHasher
{
    public static string GroupIdFor(string rawKey)
    {
        var normalizedKey = rawKey.Trim();
        var input = Encoding.UTF8.GetBytes($"clipplus.shared-key.v1:{normalizedKey}");
        var digest = SHA256.HashData(input);
        var groupBytes = digest[..16];

        return Convert.ToBase64String(groupBytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }
}
