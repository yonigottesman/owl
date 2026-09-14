import Foundation

@main
enum PowerPolicyTests {
    static func main() {
        for active in [false, true] {
            for battery in [false, true] {
                for ac in [false, true] {
                    for closed in [false, true] {
                        assert(PowerPolicy.disablesSystemSleep(active: active, batteryMode: battery, onAC: ac)
                               == (active && (battery || ac)))
                        assert(PowerPolicy.endsSession(active: active, batteryMode: battery, onAC: ac, lidClosed: closed)
                               == (active && !battery && !ac && closed))
                    }
                }
            }
        }
        assert(!PowerPolicy.disablesSystemSleep(active: true, batteryMode: false, onAC: nil))
        assert(PowerPolicy.endsSession(active: true, batteryMode: false, onAC: nil, lidClosed: true))
        assert(!PowerPolicy.endsSession(active: true, batteryMode: false, onAC: false, lidClosed: nil))
        assert(PowerPolicy.percentage(current: 500, maximum: 5000) == 10)
        assert(PowerPolicy.percentage(current: -1, maximum: 100) == nil)
        assert(PowerPolicy.percentage(current: 1, maximum: 0) == nil)
        for active in [false, true] {
            for enabled in [false, true] {
                for ac: Bool? in [true, false, nil] {
                    for level: Double? in [nil, -1, 0, 9, 10, 10.1, 11, 100, .nan] {
                        let expected = active && enabled && ac == false && level.map { $0 >= 0 && $0 <= 10 } == true
                        assert(PowerPolicy.sleepsForLowBattery(active: active, enabled: enabled, onAC: ac, percentage: level) == expected)
                    }
                }
            }
        }
        print("Live battery percentage:", PowerPolicy.batteryPercentage().map(String.init(describing:)) ?? "unknown")
        print("Passed: low-battery threshold, both battery modes, power/lid transitions, idle sessions, unavailable sensors")
        print("Live power source:", PowerPolicy.isOnACPower().map { $0 ? "AC" : "battery" } ?? "unknown")
    }
}
