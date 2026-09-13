import Foundation

@main
enum LidDisplayTests {
    static func main() {
        var policy = LidDisplayPolicy()
        assert(!policy.shouldSleepDisplay(active: false, lidClosed: true, uptime: 0))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: false, uptime: 1))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: nil, uptime: 2))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, uptime: 3))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: true, uptime: 4))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, uptime: 8))
        assert(!policy.shouldSleepDisplay(active: true, lidClosed: false, uptime: 9))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, uptime: 10))
        assert(!policy.shouldSleepDisplay(active: false, lidClosed: true, uptime: 11))
        assert(policy.shouldSleepDisplay(active: true, lidClosed: true, uptime: 12))
        print("Passed: closed-lid display sleep, retry limit, reopen, inactive session, missing sensor")
        print("Live lid sensor:", LidSensor.isClosed().map { $0 ? "closed" : "open" } ?? "unavailable")
    }
}
