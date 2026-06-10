import ServiceManagement

protocol LoginItemService: AnyObject {
    var enabled: Bool { get }

    func setEnabled(_ enabled: Bool) throws
}

struct LoginItemManager {
    private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
    }

    func isEnabled() -> Bool {
        service.enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        try service.setEnabled(enabled)
    }
}

private final class SystemLoginItemService: LoginItemService {
    var enabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
