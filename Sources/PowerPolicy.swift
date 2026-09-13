import Foundation
import IOKit.ps

enum PowerPolicy {
    static func isOnACPower() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return nil }
        return source as String == kIOPSACPowerValue
    }

    static func disablesSystemSleep(active: Bool, batteryMode: Bool, onAC: Bool?) -> Bool {
        active && (batteryMode || onAC == true)
    }

    static func endsSession(active: Bool, batteryMode: Bool, onAC: Bool?, lidClosed: Bool?) -> Bool {
        active && !batteryMode && onAC != true && lidClosed == true
    }
}
