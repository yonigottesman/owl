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
        assert(gate.wantsAwake(request(6, 11000, next), now: 11000))
        assert(gate.deadline == 32600)
        assert(!gate.wantsAwake(request(6, 11000, next), now: 11012), "Lost heartbeat restores sleep")
        assert(!gate.wantsAwake(request(6, 11013, next), now: 11013), "Stale sessions cannot revive")
        for hours in [0, -1, 1, 12, Int.max] {
            var invalid = SessionGate()
            assert(!invalid.wantsAwake(request(hours), now: 100))
        }
        var future = SessionGate()
        assert(!future.wantsAwake(request(3, 106), now: 100))
        var stopped = SessionGate()
        assert(stopped.wantsAwake(request(9), now: 100))
        assert(stopped.deadline == 32500)
        assert(!stopped.wantsAwake(nil, now: 101))
        assert(!stopped.wantsAwake(request(9, 102), now: 102))
        print("Passed: durations, fixed deadline, expiry, heartbeat loss, stop, invalid input, replay protection")
    }
}
