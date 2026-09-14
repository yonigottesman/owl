import Foundation
import Darwin

@main
enum Helper {
    static func run(_ path: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
        catch { return false }
    }

    static func main() throws {
        guard getuid() == 0, CommandLine.arguments.count == 2,
              let uid = UInt32(CommandLine.arguments[1]), uid > 0 else { exit(1) }
        let fm = FileManager.default
        let inbox = owlRoot + "/requests"
        try HelperSetup.prepareDirectories(root: owlRoot, owner: uid)
        let marker = "/var/db/com.yonigo.Owl.active"
        var sleepDisabled = fm.fileExists(atPath: marker)
        var gate = SessionGate()
        var caffeinate: Process?
        var lidPolicy = LidDisplayPolicy()
        var lastDisplaySleepRequest: TimeInterval?
        // A persistent root-owned marker lets launchd recover after a crash/reboot.
        if sleepDisabled {
            guard run("/usr/bin/pmset", ["-a", "disablesleep", "0"]) else { exit(1) }
            try fm.removeItem(atPath: marker)
            sleepDisabled = false
        }
        // Never replay a request left by a previous helper instance.
        if let data = fm.contents(atPath: inbox + "/request.json"),
           let old = try? JSONDecoder().decode(Request.self, from: data) {
            gate.finished = old.id
        }
        while true {
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
                // Finish the session so stale heartbeats cannot restart it after wake.
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
                if process.isRunning { process.terminate(); process.waitUntilExit() }
                caffeinate = nil
            }
            if wanted && caffeinate?.isRunning != true {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                // Keep work running without keeping the display lit or waking it.
                p.arguments = ["-ims", "-w", String(getpid())]
                try? p.run(); caffeinate = p
            }
            let active = wanted || sleepDisabled
            if lidPolicy.shouldSleepDisplay(active: active, lidClosed: lidClosed,
                                            uptime: ProcessInfo.processInfo.systemUptime) {
                if run("/usr/bin/pmset", ["displaysleepnow"]) {
                    lastDisplaySleepRequest = now
                } else {
                    error = "macOS could not turn off the display."
                }
            }
            let status = Status(id: request?.id, active: active,
                                deadline: active ? gate.deadline : nil, error: error, updated: now,
                                lidClosed: lidClosed, displaySleepRequestedAt: lastDisplaySleepRequest,
                                onACPower: onAC)
            try JSONEncoder().encode(status).write(to: URL(fileURLWithPath: owlRoot + "/status.json"), options: .atomic)
            chmod(owlRoot + "/status.json", 0o644)
            if shouldSleep && !sleepDisabled {
                _ = run("/usr/bin/pmset", ["sleepnow"])
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
