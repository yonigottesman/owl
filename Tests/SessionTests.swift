import Foundation

@main
enum SessionTests {
    static func main() {
        let id = UUID()
        func request(_ hours: Int = 3, _ heartbeat: Double = 100, _ session: UUID = id) -> Request {
            Request(id: session, hours: hours, heartbeat: heartbeat, pid: 123)
        }
        var gate = SessionGate()
        assert(gate.wantsAwake(request(), now: 100))
        assert(gate.deadline == 10900)
        assert(gate.wantsAwake(request(9, 200), now: 200))
        assert(gate.deadline == 10900, "A heartbeat must not extend the session")
        assert(!gate.wantsAwake(request(3, 10900), now: 10900))
        assert(!gate.wantsAwake(request(3, 10901), now: 10901), "Expired IDs must not restart")
        let next = UUID()
        assert(gate.wantsAwake(request(3, 11000, next), now: 11000))
        assert(gate.deadline == 21800)
        assert(!gate.wantsAwake(request(3, 11000, next), now: 11012), "Lost heartbeat restores sleep")
        assert(!gate.wantsAwake(request(3, 11013, next), now: 11013), "Stale sessions cannot revive")
        for hours in [-1, 2, 12, Int.max] {
            var invalid = SessionGate()
            assert(!invalid.wantsAwake(request(hours), now: 100))
        }
        for hours in [1, 3, 6, 9] {
            var timed = SessionGate()
            assert(timed.wantsAwake(request(hours), now: 100))
            assert(timed.deadline == 100 + Double(hours * 3600))
            assert(!timed.wantsAwake(request(hours, 100 + Double(hours * 3600)), now: 100 + Double(hours * 3600)))
        }
        var future = SessionGate()
        assert(!future.wantsAwake(request(3, 106), now: 100))
        var stopped = SessionGate()
        assert(stopped.wantsAwake(request(9), now: 100))
        assert(stopped.deadline == 32500)
        assert(!stopped.wantsAwake(nil, now: 101))
        assert(!stopped.wantsAwake(request(9, 102), now: 102))
        var unlimited = SessionGate()
        assert(unlimited.wantsAwake(request(0), now: 100))
        assert(unlimited.deadline == nil)
        assert(unlimited.wantsAwake(request(0, 1000000), now: 1000000), "Unlimited sessions have no deadline")
        assert(unlimited.wantsAwake(request(3, 1000001), now: 1000001))
        assert(unlimited.deadline == nil, "Heartbeats cannot change the original duration")
        assert(!unlimited.wantsAwake(request(0, 1000001), now: 1000013), "Unlimited sessions still require a heartbeat")
        assert(!unlimited.wantsAwake(request(0, 1000014), now: 1000014), "Lost unlimited sessions cannot revive")
        var unlimitedStop = SessionGate()
        assert(unlimitedStop.wantsAwake(request(0), now: 100))
        let status = Status(active: true, deadline: unlimitedStop.deadline)
        let encoded = try! JSONEncoder().encode(status)
        assert((try! JSONDecoder().decode(Status.self, from: encoded)).deadline == nil)
        assert(!unlimitedStop.wantsAwake(nil, now: 101))
        assert(!unlimitedStop.wantsAwake(request(0, 102), now: 102))
        print("Passed: unlimited sessions, JSON round trip, durations, fixed deadline, expiry, heartbeat loss, stop, invalid input, replay protection")
    }
}
