import Foundation
import Darwin

// Watches directory changes so atomic file replacement is observed as well.
final class FileEvents {
    private let source: DispatchSourceFileSystemObject
    init?(directory: String, queue: DispatchQueue = .main, changed: @escaping () -> Void) {
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(fd) }
        source.resume()
    }
    deinit { source.cancel() }
}
