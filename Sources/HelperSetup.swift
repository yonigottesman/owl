import Foundation
import Darwin

enum HelperSetup {
    static func prepareDirectories(root: String, owner: uid_t) throws {
        let fm = FileManager.default
        let inbox = root + "/requests"
        // Intermediate-directory mode also accepts an existing directory. The
        // non-intermediate API throws EEXIST on every restart after installation.
        for (path, mode) in [(root, 0o755), (inbox, 0o700)] {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: mode])
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
                throw NSError(domain: "OwlHelper", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Expected a directory at \(path)"])
            }
        }
        guard chown(inbox, owner, UInt32.max) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
