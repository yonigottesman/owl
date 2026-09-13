import Foundation
import Darwin

@main
enum HelperSetupTests {
    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("owl-setup-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("runtime").path
        try HelperSetup.prepareDirectories(root: root, owner: getuid())
        let request = URL(fileURLWithPath: root + "/requests/request.json")
        try Data("existing request".utf8).write(to: request)
        for _ in 0..<3 { try HelperSetup.prepareDirectories(root: root, owner: getuid()) }
        let saved = try String(contentsOf: request, encoding: .utf8)
        assert(saved == "existing request", "Restart must preserve existing data")
        let permissions = try fm.attributesOfItem(atPath: root + "/requests")[.posixPermissions] as! NSNumber
        assert(permissions.intValue == 0o700)
        try fm.removeItem(atPath: root + "/requests")
        try Data().write(to: URL(fileURLWithPath: root + "/requests"))
        do {
            try HelperSetup.prepareDirectories(root: root, owner: getuid())
            fatalError("Must reject a file in place of the requests directory")
        } catch {}
        print("Passed: first startup, repeated startup, preserved request, permissions, invalid directory")
    }
}
