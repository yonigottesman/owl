import Foundation
import Darwin

@main
enum EventTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = DispatchQueue(label: "owl.event-test")
        let changed = DispatchSemaphore(value: 0)
        let watcher = FileEvents(directory: directory.path, queue: queue) { changed.signal() }
        assert(watcher != nil)
        assert(changed.wait(timeout: .now() + 0.2) == .timedOut, "No callbacks while idle")
        let path = directory.appendingPathComponent("request.json")
        try Data("start".utf8).write(to: path, options: .atomic)
        assert(changed.wait(timeout: .now() + 2) == .success)
        // Drain events from atomic replacement before checking deletion.
        while changed.wait(timeout: .now() + 0.1) == .success {}
        try FileManager.default.removeItem(at: path)
        assert(changed.wait(timeout: .now() + 2) == .success)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        let exited = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeProcessSource(identifier: process.processIdentifier, eventMask: .exit, queue: queue)
        source.setEventHandler { exited.signal() }
        source.resume()
        kill(process.processIdentifier, SIGKILL)
        assert(exited.wait(timeout: .now() + 2) == .success, "Process exit is delivered without heartbeat polling")
        source.cancel()
        process.waitUntilExit()
        withExtendedLifetime(watcher) {}
        print("Passed: idle silence, atomic start-file notification, stop-file notification, force-kill notification")
    }
}
