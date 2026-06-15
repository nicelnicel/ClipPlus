using System.Threading;

namespace ClipPlus.Windows;

public sealed class SingleInstanceLock : IDisposable
{
    private const string DefaultLockName = @"Local\ClipPlus.Windows.SingleInstance";
    private readonly Mutex mutex;

    private SingleInstanceLock(Mutex mutex)
    {
        this.mutex = mutex;
    }

    public static SingleInstanceLock? AcquireDefault()
    {
        return Acquire(DefaultLockName);
    }

    public static SingleInstanceLock? Acquire(string lockName)
    {
        var mutex = new Mutex(initiallyOwned: true, lockName, out var createdNew);
        if (createdNew)
        {
            return new SingleInstanceLock(mutex);
        }

        mutex.Dispose();
        return null;
    }

    public void Dispose()
    {
        try
        {
            mutex.ReleaseMutex();
        }
        catch (ApplicationException)
        {
        }

        mutex.Dispose();
    }
}
