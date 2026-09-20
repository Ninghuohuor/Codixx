import Foundation

/// Tracks the account observed for a particular Codex process, separately from
/// the on-disk credentials that will be used after a restart.
struct RuntimeAccountState: Codable, Equatable {
    var processIdentity: String?
    var accountID: UUID?

    static func resolve(previous: Self?, processIdentity: String?, configuredAccountID: UUID?) -> Self {
        if let processIdentity, let previous, previous.processIdentity == processIdentity {
            return previous
        }
        return Self(processIdentity: processIdentity, accountID: configuredAccountID)
    }
}
