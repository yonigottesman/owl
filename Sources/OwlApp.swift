import SwiftUI
import AppKit
import Darwin
import ServiceManagement

@main
struct OwlApp: App {
    @StateObject private var model = OwlModel()

    var body: some Scene {
        MenuBarExtra {
            OwlPanel(model: model)
        } label: {
            Image(nsImage: OwlIcon.image(active: model.active))
                .help(model.active ? "Owl — keeping Mac awake" : "Owl — normal sleep")
        }
        .menuBarExtraStyle(.window)
    }
}

struct OwlPanel: View {
    @ObservedObject var model: OwlModel
    @State private var quitHovered = false
    @AppStorage("durationPosition") private var durationPosition = 3.0
    private let durations = [1, 3, 6, 9, 0]
    private var selectedIndex: Int { min(4, max(0, Int(durationPosition.rounded()))) }
    private var selectedHours: Int { durations[selectedIndex] }

    var body: some View {
        VStack(spacing: 16) {
            if model.active {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(model.remainingTime)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, 4)
                }
                Button("Turn Off") { model.stop() }
                    .buttonStyle(SessionButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(model.busy)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("Keep awake").fontWeight(.medium)
                        Spacer()
                        Text(selectedHours == 0 ? "∞" : "\(selectedHours) \(selectedHours == 1 ? "hour" : "hours")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $durationPosition, in: 0...4, step: 1)
                        .accessibilityLabel("Keep awake duration")
                        .accessibilityValue(selectedHours == 0 ? "Unlimited" : "\(selectedHours) hours")
                    HStack(spacing: 0) {
                        ForEach(Array(durations.enumerated()), id: \.offset) { index, hours in
                            if index > 0 { Spacer(minLength: 0) }
                            Text(hours == 0 ? "∞" : "\(hours)")
                                .foregroundStyle(index == selectedIndex ? Color.primary : Color.secondary)
                                .frame(width: 16)
                        }
                    }
                    .font(.caption)
                }
                Button { model.start(hours: selectedHours) } label: {
                    Text(model.busy ? "Starting…" : "Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionButtonStyle())
                .disabled(model.busy)
            }
            Divider()
            Toggle(isOn: $model.keepAwakeOnBattery) {
                Text("Keep Awake on Battery")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(HoverRowToggleStyle())
            .disabled(model.active || model.busy)
            Toggle(isOn: $model.sleepOnLowBattery) {
                Text("Sleep at 10% Battery")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(HoverRowToggleStyle())
            .disabled(model.active || model.busy)
            Toggle(isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            )) {
                Text("Launch at Login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(HoverRowToggleStyle())
            .disabled(model.active || model.busy)
            Divider()
            Button { NSApp.terminate(nil) } label: {
                Text("Quit Owl")
                    .foregroundStyle(quitHovered ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(quitHovered ? 0.10 : 0))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { quitHovered = $0 }
            .keyboardShortcut("q")
        }
        .controlSize(.small)
        .tint(.orange)
        .padding(18)
        .frame(width: 300)
        .background(PanelFocusDismissal())
        .onAppear { model.panelOpened() }
    }
}

// MenuBarExtra windows can remain visible when Cmd+Tab activates another app.
// Dismiss only the panel; the model and keep-awake session keep running.
private struct PanelFocusDismissal: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }
    func updateNSView(_ nsView: FocusView, context: Context) {}

    final class FocusView: NSView {
        private var activationObserver: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.window?.orderOut(nil)
            }
        }

        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        deinit {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
        }
    }
}

private struct HoverRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverToggleRow(configuration: configuration)
    }
}

private struct HoverToggleRow: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: .constant(configuration.isOn))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering && isEnabled ? 0.10 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .onHover { hovering = $0 }
    }
}

private struct SessionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SessionButtonSurface(configuration: configuration)
    }
}

private struct SessionButtonSurface: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.24 : (hovering && isEnabled ? 0.18 : 0.10)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(hovering && isEnabled ? 0.38 : 0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

@MainActor
final class OwlModel: ObservableObject {
    @Published var active = false
    @Published var busy = false
    @Published var keepAwakeOnBattery = UserDefaults.standard.bool(forKey: "keepAwakeOnBattery") {
        didSet { UserDefaults.standard.set(keepAwakeOnBattery, forKey: "keepAwakeOnBattery") }
    }
    @Published var sleepOnLowBattery = UserDefaults.standard.object(forKey: "sleepOnLowBattery") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sleepOnLowBattery, forKey: "sleepOnLowBattery") }
    }
    @Published private(set) var deadline: TimeInterval?
    var remainingTime: String {
        guard active else { return "00:00 left" }
        guard let deadline else { return "Until turned off" }
        let minutes = Int(ceil(min(9 * 3600, max(0, deadline - Date().timeIntervalSince1970)) / 60))
        return String(format: "%02d:%02d left", minutes / 60, minutes % 60)
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var request: Request?
    private var statusEvents: FileEvents?
    private var helperExit: DispatchSourceProcess?
    private var helperPID: Int32?
    private var confirmationTimeout: DispatchWorkItem?
    private var confirmationPending = false
    private var lastError: String?
    private var lockFD: Int32 = -1

    init() {
        NSApp.setActivationPolicy(.accessory)
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Owl")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockFD = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // The helper also restores sleep if this process is force-quit.
            try? FileManager.default.removeItem(atPath: owlRoot + "/requests/request.json")
        }
        observeStatus()
        refreshStatus()
    }

    private var helperReady: Bool {
        guard let status = readStatus() else { return false }
        return status.helperVersion == owlHelperVersion &&
            status.helperPID.map { kill($0, 0) == 0 || errno == EPERM } == true &&
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
        guard !busy, !active else { return }
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
                    observeStatus()
                    await waitForHelper()
                    guard helperReady else { throw OwlError.message("The helper did not start. Please try again.") }
                }
                let r = Request(id: UUID(), hours: hours, pid: getpid(),
                                keepAwakeOnBattery: keepAwakeOnBattery, sleepOnLowBattery: sleepOnLowBattery)
                observeStatus()
                request = r
                armConfirmationTimeout()
                try write(r)
                lastError = nil
            } catch {
                confirmationTimeout?.cancel()
                confirmationPending = false
                request = nil
                busy = false
                showError(error.localizedDescription)
            }
        }
    }

    func stop() {
        do {
            let path = owlRoot + "/requests/request.json"
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            request = nil
            busy = true
            armConfirmationTimeout()
            refreshStatus()
        } catch { showError(error.localizedDescription) }
    }

    private func write(_ r: Request) throws {
        try JSONEncoder().encode(r).write(to: URL(fileURLWithPath: owlRoot + "/requests/request.json"), options: .atomic)
    }

    func panelOpened() { refreshStatus() }

    private func observeStatus() {
        statusEvents = FileEvents(directory: owlRoot) { [weak self] in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    private func waitForHelper() async {
        if helperReady { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var watcher: FileEvents?
            var timeout: DispatchWorkItem?
            var finished = false
            let finish: () -> Void = {
                guard !finished else { return }
                finished = true
                watcher = nil
                timeout?.cancel()
                continuation.resume()
            }
            watcher = FileEvents(directory: owlRoot) { [weak self] in
                Task { @MainActor in
                    if self?.helperReady == true { finish() }
                }
            }
            let work = DispatchWorkItem { finish() }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
            if helperReady { finish() }
            _ = watcher
        }
    }

    private func armConfirmationTimeout() {
        confirmationPending = true
        confirmationTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.busy else { return }
            // Remove an unconfirmed start so it cannot become active later.
            try? FileManager.default.removeItem(atPath: owlRoot + "/requests/request.json")
            self.request = nil
            self.confirmationPending = false
            self.busy = false
            self.showError("The helper did not confirm the change. Please try again.")
        }
        confirmationTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func refreshStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        guard let status = readStatus() else { return }
        if helperPID != status.helperPID {
            helperExit?.cancel()
            helperExit = nil
            helperPID = status.helperPID
            if let pid = status.helperPID {
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
                source.setEventHandler { [weak self] in
                    Task { @MainActor in
                        guard let self, self.helperPID == pid else { return }
                        self.request = nil
                        self.confirmationTimeout?.cancel()
                        self.busy = false
                        // Keep the last confirmed state until launchd's recovery reports normal sleep.
                        if self.active { self.showError("Owl's helper is restarting and restoring normal sleep.") }
                    }
                }
                source.resume()
                helperExit = source
            }
        }
        active = status.active
        deadline = status.deadline
        if let message = status.error {
            request = nil; busy = false
            confirmationTimeout?.cancel()
            showError(message)
        }
        if let r = request, status.id == r.id {
            busy = false
            confirmationTimeout?.cancel()
            if !status.active { request = nil }
        } else if request == nil && !status.active && confirmationPending {
            busy = false
            confirmationTimeout?.cancel()
        }
        if !busy { confirmationPending = false }
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
