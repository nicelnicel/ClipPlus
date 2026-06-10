import Darwin
import Foundation

struct LoginItemSmokeTestResult: Equatable {
    let enabledAfterRegister: Bool
    let disabledAfterUnregister: Bool
    let restoredOriginal: Bool

    var passed: Bool {
        enabledAfterRegister && disabledAfterUnregister && restoredOriginal
    }
}

enum LoginItemSmokeTest {
    static func runIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        makeManager: () -> LoginItemManager = { LoginItemManager() }
    ) {
        guard environment["CLIPPLUS_LOGIN_ITEM_SMOKE_TEST"] == "1" else {
            return
        }

        let manager = makeManager()
        do {
            let result = try perform(manager: manager)
            print(
                "login_item_smoke_test enabled_after_register=\(result.enabledAfterRegister) " +
                "disabled_after_unregister=\(result.disabledAfterUnregister) " +
                "restored_original=\(result.restoredOriginal)"
            )
            fflush(stdout)

            exit(result.passed ? EXIT_SUCCESS : 2)
        } catch {
            fputs(
                "login_item_smoke_test failed error=\(error)\n",
                stderr
            )
            fflush(stderr)
            exit(1)
        }
    }

    static func perform(manager: LoginItemManager) throws -> LoginItemSmokeTestResult {
        let originalEnabled = manager.isEnabled()

        do {
            try manager.setEnabled(true)
            let enabledAfterRegister = manager.isEnabled()

            try manager.setEnabled(false)
            let disabledAfterUnregister = !manager.isEnabled()

            try manager.setEnabled(originalEnabled)
            let restoredOriginal = manager.isEnabled() == originalEnabled

            return LoginItemSmokeTestResult(
                enabledAfterRegister: enabledAfterRegister,
                disabledAfterUnregister: disabledAfterUnregister,
                restoredOriginal: restoredOriginal
            )
        } catch {
            try? manager.setEnabled(originalEnabled)
            throw error
        }
    }
}
