public enum PostSwitchAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case notifyRestartRecommended
    case restartCodexApp

    public var id: String { rawValue }
}
