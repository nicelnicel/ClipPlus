import Darwin
import Foundation

enum CoreBridgeSmokeTest {
    private static let expectedTestGroupId = "21YR2N3_wcdRPmEMLiuLMA"

    static func runIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["CLIPPLUS_COREBRIDGE_SMOKE_TEST"] == "1" else {
            return
        }

        let groupId = CoreBridge().deriveGroupId(for: "clipplus-test-key")
        print("corebridge_smoke_test group_id=\(groupId ?? "<nil>")")
        fflush(stdout)

        exit(groupId == expectedTestGroupId ? EXIT_SUCCESS : 2)
    }
}
