import Foundation

@main
enum SessionTests {
    static func main() {
        func request(_ hours: Int, id: UUID = UUID(), battery: Bool = true, low: Bool = true) -> Request {
            Request(id: id, hours: hours, pid: 123, keepAwakeOnBattery: battery, sleepOnLowBattery: low)
        }
        for hours in [1, 3, 6, 9] {
            var gate = SessionGate()
            let r = request(hours)
            assert(gate.wantsAwake(r, now: 100))
            let expiry = 100 + Double(hours * 3600)
            assert(gate.deadline == expiry)
            assert(gate.wantsAwake(r, now: expiry - 1), "No heartbeat is needed")
            assert(!gate.wantsAwake(r, now: expiry))
            assert(!gate.wantsAwake(r, now: expiry + 1), "Expired requests cannot restart")
        }
        var immutable = SessionGate()
        let original = request(3)
        assert(immutable.wantsAwake(original, now: 100))
        assert(immutable.wantsAwake(request(0, id: original.id, battery: false, low: false), now: 1000))
        assert(immutable.session?.hours == 3)
        assert(immutable.session?.keepAwakeOnBattery == true)
        assert(immutable.session?.sleepOnLowBattery == true)
        assert(immutable.deadline == 10900)
        assert(immutable.wantsAwake(request(9), now: 2000))
        assert(immutable.id == original.id, "A second start cannot replace a running session")
        immutable.stop() // Process exit, low battery, stop and expiry share this path.
        assert(!immutable.wantsAwake(original, now: 2001))
        assert(immutable.session == nil && immutable.deadline == nil)
        assert(immutable.wantsAwake(request(6), now: 2002))
        var unlimited = SessionGate()
        let forever = request(0)
        assert(unlimited.wantsAwake(forever, now: 100))
        assert(unlimited.wantsAwake(forever, now: 1_000_000))
        assert(unlimited.deadline == nil)
        let data = try! JSONEncoder().encode(forever)
        assert(!String(decoding: data, as: UTF8.self).contains("heartbeat"))
        assert((try! JSONDecoder().decode(Request.self, from: data)).id == forever.id)
        assert(!unlimited.wantsAwake(nil, now: 1_000_001))
        assert(!unlimited.wantsAwake(forever, now: 1_000_002))
        for hours in [-1, 2, 12, Int.max] {
            var gate = SessionGate()
            assert(!gate.wantsAwake(request(hours), now: 100))
        }
        var recovered = SessionGate()
        recovered.finished = forever.id
        assert(!recovered.wantsAwake(forever, now: 200), "Helper restart must not replay a request")
        print("Passed: immutable settings, no heartbeat, timed expiry, indefinite sessions, stop/process-exit replay protection, restart recovery")
    }
}
