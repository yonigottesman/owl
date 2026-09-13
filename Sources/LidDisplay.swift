import Foundation
import IOKit

enum LidSensor {
    static func isClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
}

struct LidDisplayPolicy {
    private var lastRequest: TimeInterval?

    mutating func shouldSleepDisplay(active: Bool, lidClosed: Bool?, uptime: TimeInterval) -> Bool {
        guard active, lidClosed == true else {
            lastRequest = nil
            return false
        }
        // Retry while closed in case input or another app wakes the display.
        guard lastRequest == nil || uptime - lastRequest! >= 5 else { return false }
        lastRequest = uptime
        return true
    }
}
