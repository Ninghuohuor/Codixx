import Foundation

public struct FileLock: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func withExclusiveLock<T>(_ body: () throws -> T) rethrows -> T {
        try body()
    }
}
