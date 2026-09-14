import Foundation
import IOKit
import CoreGraphics

enum LidSensor {
    static func isClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
}

enum DisplaySensor {
    static func hasExternalDisplay() -> Bool? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        // Online includes mirrored and sleeping displays, not just active ones.
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success,
              count > 0 else { return nil }
        guard count < displays.count else { return nil }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}

struct LidDisplayPolicy {
    private var requested = false

    mutating func shouldSleepDisplay(active: Bool, lidClosed: Bool?, externalDisplay: Bool?) -> Bool {
        // Never blank a monitor, or guess when display detection is unavailable.
        guard active, lidClosed == true, externalDisplay == false else {
            requested = false
            return false
        }
        // One request on lid-close/start/unplug, not repeated on battery notifications.
        guard !requested else { return false }
        requested = true
        return true
    }
}
