import Foundation

let owlRoot = "/var/run/com.yonigo.Owl"
let owlLabel = "com.yonigo.Owl.helper"
let owlHelperVersion = 6

struct Request: Codable {
    let id: UUID
    let hours: Int
    let heartbeat: TimeInterval
    let pid: Int32
    var keepAwakeOnBattery: Bool? = nil
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
    var onACPower: Bool?
}

// A session's deadline is established once. Heartbeats can never extend it.
struct SessionGate {
    var id: UUID?
    var deadline: TimeInterval?
    var finished: UUID?

    mutating func wantsAwake(_ request: Request?, now: TimeInterval) -> Bool {
        guard let r = request, [0, 3, 9].contains(r.hours),
              r.heartbeat <= now + 5, now - r.heartbeat < 12 else {
            if let id { finished = id }
            id = nil
            return false
        }
        guard r.id != finished else { return false }
        if id != r.id {
            id = r.id
            // Zero means no time limit; heartbeat and stop rules still apply.
            deadline = r.hours == 0 ? nil : now + Double(r.hours * 3600)
        }
        if let deadline, now >= deadline {
            finished = r.id
            id = nil
            return false
        }
        return true
    }
}
