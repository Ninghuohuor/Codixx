import AppKit
import CodixxCore
import Darwin
import Foundation

final class SingleInstanceGuard {
    static let activationNotificationName = Notification.Name("CodixxActivateExistingInstance")

    private let lockFileDescriptor: Int32

    private init(lockFileDescriptor: Int32) {
        self.lockFileDescriptor = lockFileDescriptor
    }

    deinit {
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
    }

    static func acquire(paths: CodixxPaths = CodixxPaths()) -> SingleInstanceGuard? {
        do {
            try paths.createApplicationSupportDirectories()
        } catch {
            return nil
        }

        let lockURL = paths.applicationSupport.appendingPathComponent("codixx.pid")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            DistributedNotificationCenter.default().postNotificationName(
                activationNotificationName,
                object: Bundle.main.bundleIdentifier
            )
            return nil
        }

        ftruncate(fd, 0)
        let pid = "\(getpid())\n"
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        return SingleInstanceGuard(lockFileDescriptor: fd)
    }
}
