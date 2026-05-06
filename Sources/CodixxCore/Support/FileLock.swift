import Foundation
import Darwin

public enum FileLockError: Error, Equatable, LocalizedError {
    case timedOut(String)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let path):
            return "Timed out acquiring file lock at \(path)"
        case .openFailed(let path):
            return "Could not open file lock at \(path)"
        }
    }
}

public struct FileLock: Sendable {
    public let url: URL
    public let timeoutSeconds: TimeInterval

    public init(url: URL, timeoutSeconds: TimeInterval = 3) {
        self.url = url
        self.timeoutSeconds = timeoutSeconds
    }

    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw FileLockError.openFailed(url.path)
        }
        defer { close(fd) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if timeoutSeconds <= 0 || Date() >= deadline {
                throw FileLockError.timedOut(url.path)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { flock(fd, LOCK_UN) }

        return try body()
    }
}
