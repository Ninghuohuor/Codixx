public enum PostSwitchAction: String, Codable, Sendable {
    case none
    case notifyRestartRecommended
    case restartCodexApp
}
