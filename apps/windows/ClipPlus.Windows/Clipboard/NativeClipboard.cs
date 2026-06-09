namespace ClipPlus.Windows.Clipboard;

public sealed class NativeClipboard
{
    public string? ReadText()
    {
        return System.Windows.Clipboard.ContainsText()
            ? System.Windows.Clipboard.GetText()
            : null;
    }

    public void WriteText(string text)
    {
        System.Windows.Clipboard.SetText(text);
    }
}
