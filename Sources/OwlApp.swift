import SwiftUI
import AppKit
import Darwin
import ServiceManagement

@main
struct OwlApp: App {
    @StateObject private var model = OwlModel()

    var body: some Scene {
        MenuBarExtra {
            if model.active {
                Text(model.remainingTime)
                    .monospacedDigit()
                Button("Turn Off") { model.stop() }.disabled(model.busy)
            } else {
                ForEach([3, 0, 9], id: \.self) { hours in
                    Button(hours == 0 ? "Indefinitely" : "\(hours) hours") { model.start(hours: hours) }.disabled(model.busy)
                }
            }
            Divider()
            Toggle("Keep Awake on Battery", isOn: $model.keepAwakeOnBattery)
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Button("Quit Owl") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: OwlIcon.image(active: model.active))
                .help(model.active ? "Owl — keeping Mac awake" : "Owl — normal sleep")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class OwlModel: ObservableObject {
    @Published var active = false
    @Published var busy = false
    @Published var keepAwakeOnBattery = UserDefaults.standard.bool(forKey: "keepAwakeOnBattery") {
        didSet { UserDefaults.standard.set(keepAwakeOnBattery, forKey: "keepAwakeOnBattery") }
    }
    @Published private(set) var remainingTime = "00:00 left"
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var request: Request?
    private var timer: Timer?
    private var lastError: String?
    private var lockFD: Int32 = -1
    private var pendingSince: TimeInterval?

    init() {
        NSApp.setActivationPolicy(.accessory)
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Owl")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        let heartbeatTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Keep the countdown and helper heartbeat running while the menu is open.
        RunLoop.main.add(heartbeatTimer, forMode: .common)
        timer = heartbeatTimer
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // The helper also restores sleep if this process is force-quit.
            try? FileManager.default.removeItem(atPath: owlRoot + "/requests/request.json")
        }
        tick()
    }

    private var helperReady: Bool {
        guard let status = readStatus() else { return false }
        return status.helperVersion == owlHelperVersion &&
            Date().timeIntervalSince1970 - status.updated < 8 &&
            FileManager.default.isWritableFile(atPath: owlRoot + "/requests")
    }

    private func readStatus() -> Status? {
        guard let data = FileManager.default.contents(atPath: owlRoot + "/status.json") else { return nil }
        return try? JSONDecoder().decode(Status.self, from: data)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showError("Could not change Launch at Login. " + error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start(hours: Int) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                if !helperReady {
                    guard let resources = Bundle.main.resourceURL else { throw OwlError.message("Owl's helper is missing. Rebuild the app.") }
                    let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                    let command = "/bin/bash " + quote(resources.appendingPathComponent("install-helper.sh").path) + " " +
                        quote(resources.appendingPathComponent(owlLabel).path) + " \(getuid())"
                    let script = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges with prompt \"Owl needs a helper to keep your Mac awake with the lid closed.\""
                    let result = await Task.detached { () -> (Int32, String) in
                        let p = Process(); let pipe = Pipe()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        p.arguments = ["-e", script]; p.standardError = pipe
                        do {
                            try p.run()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            p.waitUntilExit()
                            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
                        } catch { return (1, error.localizedDescription) }
                    }.value
                    if result.0 != 0 {
                        busy = false
                        if !result.1.contains("-128") { showError("Helper setup failed. " + result.1) }
                        return
                    }
                    for _ in 0..<30 {
                        if helperReady { break }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    guard helperReady else { throw OwlError.message("The helper did not start. Please try again.") }
                }
                let r = Request(id: UUID(), hours: hours, heartbeat: Date().timeIntervalSince1970, pid: getpid(),
                                keepAwakeOnBattery: keepAwakeOnBattery)
                try write(r)
                request = r
                pendingSince = Date().timeIntervalSince1970
                lastError = nil
            } catch { busy = false; showError(error.localizedDescription) }
        }
    }

    func stop() {
        do {
            let path = owlRoot + "/requests/request.json"
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            request = nil
            busy = true
            pendingSince = Date().timeIntervalSince1970
        } catch { showError(error.localizedDescription) }
    }

    private func write(_ r: Request) throws {
        try JSONEncoder().encode(r).write(to: URL(fileURLWithPath: owlRoot + "/requests/request.json"), options: .atomic)
    }

    private func tick() {
        // Reflect changes made outside Owl in System Settings as well.
        let loginEnabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != loginEnabled { launchAtLogin = loginEnabled }
        let now = Date().timeIntervalSince1970
        if let r = request {
            do { try write(Request(id: r.id, hours: r.hours, heartbeat: now, pid: r.pid,
                                   keepAwakeOnBattery: keepAwakeOnBattery)) }
            catch { request = nil; busy = false; showError("Owl lost contact with its helper. Sleep will be restored automatically.") }
        }
        guard let status = readStatus(), now - status.updated < 8 else {
            if active { showError("Owl's helper is restarting. Waiting for sleep status.") }
            if let since = pendingSince, now - since > 12 { busy = false; pendingSince = nil; request = nil }
            return
        }
        active = status.active
        if let deadline = status.deadline, deadline.isFinite {
            // Round up so a freshly started three-hour session reads 03:00.
            let minutes = Int(ceil(min(9 * 3600, max(0, deadline - now)) / 60))
            let label = String(format: "%02d:%02d left", minutes / 60, minutes % 60)
            if remainingTime != label { remainingTime = label }
        } else if status.active {
            remainingTime = "Until turned off"
        } else if remainingTime != "00:00 left" {
            remainingTime = "00:00 left"
        }
        if let message = status.error { request = nil; busy = false; pendingSince = nil; showError(message) }
        if let r = request, status.id == r.id {
            busy = false; pendingSince = nil
            if !status.active { request = nil }
        } else if request == nil && !status.active && pendingSince != nil {
            busy = false; pendingSince = nil
        }
        if let since = pendingSince, now - since > 12 {
            request = nil; busy = false; pendingSince = nil
            showError("The helper did not confirm the change. Please try again.")
        }
    }

    private func showError(_ message: String) {
        guard lastError != message else { return }
        lastError = message
        let alert = NSAlert(); alert.messageText = "Owl"; alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum OwlError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): return message } }
}
