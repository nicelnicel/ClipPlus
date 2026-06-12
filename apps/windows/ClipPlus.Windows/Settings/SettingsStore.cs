using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClipPlus.Windows.Settings;

public sealed record PersistedSettings(
    bool SharedKeyConfigured,
    bool SharingEnabled,
    string SharedGroupId
)
{
    [JsonIgnore]
    public string SharedKeyInput { get; init; } = string.Empty;
}

public sealed class SettingsStore
{
    private const string FileName = "settings.json";
    private readonly string directory;
    private readonly string filePath;
    private readonly SharedKeyVault sharedKeyVault;

    public SettingsStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ClipPlus"),
            new FileSharedKeyVault())
    {
    }

    public SettingsStore(string directory)
        : this(directory, new FileSharedKeyVault(Path.Combine(directory, FileSharedKeyVault.FileName)))
    {
    }

    public SettingsStore(string directory, SharedKeyVault sharedKeyVault)
    {
        this.directory = directory;
        filePath = Path.Combine(directory, FileName);
        this.sharedKeyVault = sharedKeyVault;
    }

    public PersistedSettings Load()
    {
        if (!File.Exists(filePath))
        {
            return DefaultSettings();
        }

        try
        {
            var settings = JsonSerializer.Deserialize<PersistedSettings>(File.ReadAllText(filePath))
                ?? DefaultSettings();
            var sharedGroupId = settings.SharedGroupId.Trim();
            var sharedKeyInput = sharedKeyVault.LoadSharedKey().Trim();

            return settings with
            {
                SharedKeyConfigured = settings.SharedKeyConfigured
                    && !string.IsNullOrEmpty(sharedGroupId)
                    && !string.IsNullOrEmpty(sharedKeyInput),
                SharedGroupId = sharedGroupId,
                SharedKeyInput = sharedKeyInput
            };
        }
        catch (JsonException)
        {
            return DefaultSettings();
        }
        catch (IOException)
        {
            return DefaultSettings();
        }
    }

    public void Save(SettingsState state)
    {
        Save(new PersistedSettings(
            SharedKeyConfigured: state.SharedKeyConfigured,
            SharingEnabled: state.SharingEnabled,
            SharedGroupId: state.SharedGroupId
        )
        {
            SharedKeyInput = state.SharedKeyInput
        });
    }

    public void Save(PersistedSettings settings)
    {
        Directory.CreateDirectory(directory);
        var sharedGroupId = settings.SharedGroupId.Trim();
        var sharedKeyInput = settings.SharedKeyInput.Trim();
        var normalizedSettings = settings with
        {
            SharedKeyConfigured = settings.SharedKeyConfigured
                && !string.IsNullOrEmpty(sharedGroupId)
                && !string.IsNullOrEmpty(sharedKeyInput),
            SharedGroupId = sharedGroupId,
            SharedKeyInput = sharedKeyInput
        };

        if (!string.IsNullOrEmpty(sharedKeyInput))
        {
            sharedKeyVault.SaveSharedKey(sharedKeyInput);
        }

        File.WriteAllText(filePath, JsonSerializer.Serialize(normalizedSettings));
    }

    private static PersistedSettings DefaultSettings()
    {
        return new PersistedSettings(
            SharedKeyConfigured: false,
            SharingEnabled: true,
            SharedGroupId: string.Empty
        );
    }
}
