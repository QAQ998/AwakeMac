import ServiceManagement

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

extension SMAppService: LoginItemServicing {
    func openSystemSettings() {
        Self.openSystemSettingsLoginItems()
    }
}
