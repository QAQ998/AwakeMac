import Foundation

let helperDelegate = PowerHelperListenerDelegate()
let helperListener = NSXPCListener(machServiceName: powerHelperMachServiceName)
helperListener.delegate = helperDelegate
helperListener.resume()
RunLoop.main.run()

