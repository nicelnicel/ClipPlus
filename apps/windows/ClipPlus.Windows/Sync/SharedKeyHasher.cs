namespace ClipPlus.Windows.Sync;

public static class SharedKeyHasher
{
    public static string GroupIdFor(string rawKey)
    {
        var rustGroupId = new ClipPlus.Windows.CoreBridge.CoreBridge().DeriveGroupId(rawKey);
        if (!string.IsNullOrEmpty(rustGroupId))
        {
            return rustGroupId;
        }

        throw new InvalidOperationException("Rust core library is unavailable; cannot derive shared group id.");
    }
}
