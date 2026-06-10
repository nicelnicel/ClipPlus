namespace ClipPlus.Windows.CoreBridge;

using System.IO;

internal static class CoreBridgeSmokeTest
{
    public static void RunIfRequested()
    {
        if (Environment.GetEnvironmentVariable("CLIPPLUS_COREBRIDGE_SMOKE_TEST") != "1")
        {
            return;
        }

        var coreBridge = new CoreBridge();
        var groupId = coreBridge.DeriveGroupId("clipplus-test-key");
        var output = groupId is null
            ? "corebridge_smoke_test failed"
            : $"corebridge_smoke_test group_id={groupId}";
        if (groupId is null)
        {
            output = $"{output}{Environment.NewLine}{string.Join(Environment.NewLine, coreBridge.FfiLoadDiagnostics())}";
        }

        var outputPath = Environment.GetEnvironmentVariable("CLIPPLUS_COREBRIDGE_SMOKE_TEST_OUTPUT");
        if (!string.IsNullOrWhiteSpace(outputPath))
        {
            File.WriteAllText(outputPath, output);
        }

        Environment.Exit(groupId == "21YR2N3_wcdRPmEMLiuLMA" ? 0 : 2);
    }
}
