import Foundation

let owlRoot = "/var/run/com.yonigo.Owl"
let owlLabel = "com.yonigo.Owl.helper"
let owlHelperVersion = 10

struct Request: Codable {
    let id: UUID
    let hours: Int
    let pid: Int32
    var keepAwakeOnBattery: Bool? = nil
    var sleepOnLowBattery: Bool? = nil
}

struct Status: Codable {
    var helperVersion: Int? = owlHelperVersion
    var id: UUID?
    var active: Bool = false
    var deadline: TimeInterval?
    var error: String?
    var updated: TimeInterval = Date().timeIntervalSince1970
    var lidClosed: Bool?
    var displaySleepRequestedAt: TimeInterval?
    var helperPID: Int32?
    var onACPower: Bool?
}

// The start request is an immutable snapshot. Events may end it, never change it.
struct SessionGate {
    private(set) var session: Request?
    var id: UUID? { session?.id }
    private(set) var deadline: TimeInterval?
    var finished: UUID?

    mutating func stop() {
        if let session { finished = session.id }
        session = nil
        deadline = nil
    }

    mutating func wantsAwake(_ request: Request?, now: TimeInterval) -> Bool {
        guard let r = request, [0, 1, 3, 6, 9].contains(r.hours), r.pid > 0 else {
            stop()
            return false
        }
        guard r.id != finished else { return false }
        if session == nil {
            session = r
            deadline = r.hours == 0 ? nil : now + Double(r.hours * 3600)
        }
        if let deadline, now >= deadline {
            stop()
            return false
        }
        return true
    }
}
