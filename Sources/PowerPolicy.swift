import Foundation
import IOKit.ps

enum PowerPolicy {
    static func isOnACPower() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return nil }
        return source as String == kIOPSACPowerValue
    }

    static func batteryPercentage() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = values[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = values[kIOPSMaxCapacityKey] as? NSNumber else { continue }
            return percentage(current: current.doubleValue, maximum: maximum.doubleValue)
        }
        return nil
    }

    static func percentage(current: Double, maximum: Double) -> Double? {
        guard current.isFinite, maximum.isFinite, maximum > 0, current >= 0, current <= maximum else { return nil }
        return current / maximum * 100
    }

    static func sleepsForLowBattery(active: Bool, enabled: Bool, onAC: Bool?, percentage: Double?) -> Bool {
        guard active, enabled, onAC == false, let percentage,
              percentage.isFinite, percentage >= 0 else { return false }
        return percentage <= 10
    }

    static func disablesSystemSleep(active: Bool, batteryMode: Bool, onAC: Bool?) -> Bool {
        active && (batteryMode || onAC == true)
    }

    static func endsSession(active: Bool, batteryMode: Bool, onAC: Bool?, lidClosed: Bool?) -> Bool {
        active && !batteryMode && onAC != true && lidClosed == true
    }
}
