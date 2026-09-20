import Foundation

/// Tracks the account observed for a particular Codex process, separately from
/// API credentials written externally may need a restart, whereas ChatGPT
/// login completed inside Codex can change the account in the same process.
struct RuntimeAccountState: Codable, Equatable {
    var processIdentity: String?
    var accountID: UUID?

    static func resolve(previous: Self?, processIdentity: String?, configuredAccountID: UUID?, isChatGPTLogin: Bool = false) -> Self {
        if !isChatGPTLogin, let processIdentity, let previous, previous.processIdentity == processIdentity {
            return previous
        }
        return Self(processIdentity: processIdentity, accountID: configuredAccountID)
    }
}
