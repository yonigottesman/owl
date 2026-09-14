import Foundation

@main
enum LidDisplayTests {
    static func main() {
        var policy = LidDisplayPolicy()
        assert(!policy.shouldSleepDisplay(active: false, lidClosed: true, externalDisplay: false))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: nil, externalDisplay: false))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: false))
        for _ in 0..<10 {
            assert(!policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: false), "Unrelated events must not repeatedly sleep displays")
        }
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: false, externalDisplay: false))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: false))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: true))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: nil))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: false))
        assert(!policy.shouldSleepDisplay(active: false, lidClosed: true, externalDisplay: false))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, externalDisplay: false))
        print("Passed: one display-sleep per transition, external monitor protection, unknown state, reopen, unplug and session restart")
        print("Live external display:", DisplaySensor.hasExternalDisplay().map { $0 ? "connected" : "none" } ?? "unknown")
    }
}
