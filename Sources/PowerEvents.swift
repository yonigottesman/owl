import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import CoreGraphics

// All callbacks are delivered onto the helper's main queue. No sampling timer.
final class PowerEvents {
    let changed: () -> Void
    private var powerSource: CFRunLoopSource?
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var root: io_service_t = 0
    private var displayRegistered = false

    init(changed: @escaping () -> Void) throws {
        self.changed = changed
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ pointer in
            guard let pointer else { return }
            Unmanaged<PowerEvents>.fromOpaque(pointer).takeUnretainedValue().notify()
        }, context)?.takeRetainedValue()
        guard let powerSource else { throw EventError.unavailable }
        CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
        port = IONotificationPortCreate(kIOMainPortDefault)
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard let port, root != 0 else { throw EventError.unavailable }
        IONotificationPortSetDispatchQueue(port, .main)
        guard IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { pointer, _, message, _ in
            guard let pointer, message == OwlClamshellStateChange || message == OwlSystemHasPoweredOn else { return }
            Unmanaged<PowerEvents>.fromOpaque(pointer).takeUnretainedValue().notify()
        }, context, &notifier) == KERN_SUCCESS else { throw EventError.unavailable }
        displayRegistered = CGDisplayRegisterReconfigurationCallback(Self.displayChanged, context) == .success
        guard displayRegistered else { throw EventError.unavailable }
    }

    private static let displayChanged: CGDisplayReconfigurationCallBack = { _, flags, pointer in
        guard let pointer, !flags.contains(.beginConfigurationFlag) else { return }
        Unmanaged<PowerEvents>.fromOpaque(pointer).takeUnretainedValue().notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.changed() }
    }

    deinit {
        if displayRegistered { CGDisplayRemoveReconfigurationCallback(Self.displayChanged, Unmanaged.passUnretained(self).toOpaque()) }
        if notifier != 0 { IOObjectRelease(notifier) }
        if root != 0 { IOObjectRelease(root) }
        if let port { IONotificationPortDestroy(port) }
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }
    enum EventError: Error { case unavailable }
}
