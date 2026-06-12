namespace ClipPlus.Windows.Sync;

public sealed class RemoteFileTransferGate
{
    private const int MaxCompletedCount = 128;

    private readonly object syncLock = new();
    private readonly HashSet<string> activeTransferIds = new(StringComparer.Ordinal);
    private readonly HashSet<string> completedTransferIds = new(StringComparer.Ordinal);
    private readonly Queue<string> completedOrder = new();

    public bool CanAcceptOffer(string transferId)
    {
        lock (syncLock)
        {
            return IsUsableTransferId(transferId)
                && !activeTransferIds.Contains(transferId)
                && !completedTransferIds.Contains(transferId);
        }
    }

    public bool Begin(string transferId)
    {
        lock (syncLock)
        {
            if (!IsUsableTransferId(transferId)
                || activeTransferIds.Contains(transferId)
                || completedTransferIds.Contains(transferId))
            {
                return false;
            }

            activeTransferIds.Add(transferId);
            return true;
        }
    }

    public void Complete(string transferId)
    {
        lock (syncLock)
        {
            activeTransferIds.Remove(transferId);
            if (!completedTransferIds.Add(transferId))
            {
                return;
            }

            completedOrder.Enqueue(transferId);
            while (completedOrder.Count > MaxCompletedCount)
            {
                completedTransferIds.Remove(completedOrder.Dequeue());
            }
        }
    }

    public void Fail(string transferId)
    {
        lock (syncLock)
        {
            activeTransferIds.Remove(transferId);
        }
    }

    private static bool IsUsableTransferId(string transferId)
    {
        return !string.IsNullOrWhiteSpace(transferId);
    }
}
