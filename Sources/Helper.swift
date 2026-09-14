import Foundation
import Darwin

@main
enum HelperMain {
    static func main() throws {
        guard getuid() == 0, CommandLine.arguments.count == 2,
              let uid = UInt32(CommandLine.arguments[1]), uid > 0 else { exit(1) }
        let helper = Helper(uid: uid)
        try helper.start()
        withExtendedLifetime(helper) { RunLoop.main.run() }
    }
}

final class Helper {
    let uid: UInt32
    let fm = FileManager.default
    let inbox = owlRoot + "/requests"
    let marker = "/var/db/com.yonigo.Owl.active"
    var sleepDisabled = false
    var gate = SessionGate()
    var caffeinate: Process?
    var lidPolicy = LidDisplayPolicy()
    var lastDisplaySleepRequest: TimeInterval?
    var files: FileEvents?
    var powerEvents: PowerEvents?
    var processExit: DispatchSourceProcess?
    var expiry: DispatchSourceTimer?
    var watchedID: UUID?
    var retry: DispatchWorkItem?
    var signals: [DispatchSourceSignal] = []
    var pendingSleep = false

    init(uid: UInt32) { self.uid = uid }

    func run(_ path: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
        catch { return false }
    }

    func start() throws {
        try HelperSetup.prepareDirectories(root: owlRoot, owner: uid)
        if fm.fileExists(atPath: marker) {
            guard run("/usr/bin/pmset", ["-a", "disablesleep", "0"]) else { exit(1) }
            try fm.removeItem(atPath: marker)
        }
        if let data = fm.contents(atPath: inbox + "/request.json"),
           let old = try? JSONDecoder().decode(Request.self, from: data) {
            gate.finished = old.id
        }
        files = FileEvents(directory: inbox) { [weak self] in self?.handleEvent() }
        guard files != nil else { exit(1) }
        powerEvents = try PowerEvents { [weak self] in
            guard let self, self.gate.session != nil || self.sleepDisabled else { return }
            self.handleEvent()
        }
        for code in [SIGTERM, SIGINT, SIGHUP] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { exit(0) }
                self.gate.stop()
                self.handleEvent()
                exit(0)
            }
            source.resume()
            signals.append(source)
        }
        handleEvent()
    }

    func watchSession() {
        guard watchedID != gate.id else { return }
        processExit?.cancel(); processExit = nil
        expiry?.cancel(); expiry = nil
        watchedID = gate.id
        guard let session = gate.session else { return }
        let source = DispatchSource.makeProcessSource(identifier: session.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.gate.id == session.id else { return }
            self.gate.stop()
            self.handleEvent()
        }
        source.resume()
        processExit = source
        if kill(session.pid, 0) != 0 {
            gate.stop()
            DispatchQueue.main.async { [weak self] in self?.handleEvent() }
        }
        if let deadline = gate.deadline {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            let time = timespec(tv_sec: Int(deadline), tv_nsec: Int((deadline - floor(deadline)) * 1_000_000_000))
            timer.schedule(wallDeadline: DispatchWallTime(timespec: time))
            timer.setEventHandler { [weak self] in self?.handleEvent() }
            timer.resume()
            expiry = timer
        }
    }

    func handleEvent() {
        do { try reconcile() }
        catch {
            gate.stop()
            if let caffeinate, caffeinate.isRunning { caffeinate.terminate() }
            if fm.fileExists(atPath: marker) { _ = run("/usr/bin/pmset", ["-a", "disablesleep", "0"]) }
            exit(1) // launchd restarts and performs persistent-marker recovery.
        }
    }

    func reconcile() throws {
        let now = Date().timeIntervalSince1970
        var request: Request?
        // Bound the input; this helper accepts data only, never commands or paths.
        let fd = open(inbox + "/request.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd >= 0 {
            var info = stat()
            if fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
               info.st_uid == uid, info.st_size <= 4096 {
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
                let data = handle.readData(ofLength: 4096)
                request = try? JSONDecoder().decode(Request.self, from: data)
            }
            close(fd)
        }
        if let r = request, r.pid <= 0 || kill(r.pid, 0) != 0 { request = nil }
        var wanted = gate.wantsAwake(request, now: now)
        request = gate.session ?? request
        watchSession()
        let onAC = PowerPolicy.isOnACPower()
        let lidClosed = LidSensor.isClosed()
        let batteryMode = request?.keepAwakeOnBattery ?? false
        let sleepForClosedLid = PowerPolicy.endsSession(active: wanted, batteryMode: batteryMode,
                                                        onAC: onAC, lidClosed: lidClosed)
        let sleepForLowBattery = PowerPolicy.sleepsForLowBattery(
            active: wanted, enabled: request?.sleepOnLowBattery ?? false,
            onAC: onAC, percentage: PowerPolicy.batteryPercentage())
        let shouldSleep = sleepForClosedLid || sleepForLowBattery
        if shouldSleep {
            pendingSleep = true
            // Finish the session so stale start requests cannot restart it after wake.
            wanted = gate.wantsAwake(nil, now: now)
        }
        let disableSleep = PowerPolicy.disablesSystemSleep(active: wanted, batteryMode: batteryMode, onAC: onAC)
        var error: String?
        if disableSleep && !sleepDisabled {
            // Refuse to take over another keep-awake tool's global sleep setting.
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["-g"]; p.standardOutput = pipe
            try p.run()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            if p.terminationStatus != 0 || output.range(of: #"(?:disablesleep|SleepDisabled)\s+1"#, options: .regularExpression) != nil {
                error = "Sleep is already disabled by another tool. Turn that tool off first."
                gate.finished = request?.id
            } else {
                try Data("active".utf8).write(to: URL(fileURLWithPath: marker), options: .atomic)
                sleepDisabled = run("/usr/bin/pmset", ["-a", "disablesleep", "1"])
                if !sleepDisabled { error = "macOS could not disable sleep."; gate.finished = request?.id }
            }
        }
        if !disableSleep && (sleepDisabled || fm.fileExists(atPath: marker)) {
            if run("/usr/bin/pmset", ["-a", "disablesleep", "0"]) {
                sleepDisabled = false
                try? fm.removeItem(atPath: marker)
            } else { error = "Could not restore sleep. Owl will keep retrying." }
        }
        if error != nil { wanted = gate.wantsAwake(nil, now: now) }
        if !wanted, let process = caffeinate {
            process.terminationHandler = nil
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            caffeinate = nil
        }
        if wanted && caffeinate?.isRunning != true {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            // Keep work running without keeping the display lit or waking it.
            p.arguments = ["-ims", "-w", String(getpid())]
            try p.run()
            caffeinate = p
            let sessionID = gate.id
            p.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.gate.id == sessionID else { return }
                    self.gate.stop()
                    self.handleEvent()
                }
            }
        }
        watchSession()
        let active = wanted || sleepDisabled
        if lidPolicy.shouldSleepDisplay(active: active, lidClosed: lidClosed,
                                        externalDisplay: DisplaySensor.hasExternalDisplay()) {
            if run("/usr/bin/pmset", ["displaysleepnow"]) {
                lastDisplaySleepRequest = now
            } else {
                error = "macOS could not turn off the display."
            }
        }
        let status = Status(id: request?.id, active: active,
                            deadline: active ? gate.deadline : nil, error: error, updated: now,
                            lidClosed: lidClosed, displaySleepRequestedAt: lastDisplaySleepRequest,
                            helperPID: getpid(), onACPower: onAC)
        try JSONEncoder().encode(status).write(to: URL(fileURLWithPath: owlRoot + "/status.json"), options: .atomic)
        chmod(owlRoot + "/status.json", 0o644)
        retry?.cancel()
        retry = nil
        if !wanted && (sleepDisabled || fm.fileExists(atPath: marker)) {
            // Retry only a failed cleanup, never an ordinary active session.
            let work = DispatchWorkItem { [weak self] in self?.handleEvent() }
            retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
        if pendingSleep && !active {
            pendingSleep = false
            _ = run("/usr/bin/pmset", ["sleepnow"])
        }
    }
}
