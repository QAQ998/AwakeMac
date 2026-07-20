import Foundation

let powerHelperMachServiceName = "com.zhuhai.AwakeMac.PowerHelper"
let powerHelperPlistName = "com.zhuhai.AwakeMac.PowerHelper.plist"

@objc protocol PowerHelperProtocol {
    func enableLidMode(
        leaseID: String,
        hardDeadline: Date?,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func renewLease(leaseID: String, reply: @escaping @Sendable (Bool) -> Void)
    func disableLidMode(reply: @escaping @Sendable (Bool, String?) -> Void)
    func status(reply: @escaping @Sendable (Bool, Date?) -> Void)
}
