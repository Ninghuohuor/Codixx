import XCTest
@testable import CodixxCore

final class RateLimitReaderTests: XCTestCase {
    func testFirstParseReturnsObservationAndAdvancesCursorThenSecondParseReturnsNoDuplicate() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: session
        )
        let cursorStore = ParseCursorStore(paths: paths)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore)

        let first = try reader.readNewObservations()
        let cursorAfterFirst = try cursorStore.load().offset(for: session)
        let second = try reader.readNewObservations()

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.primaryUsedPercent, 82)
        XCTAssertEqual(first.first?.primaryWindowMinutes, 300)
        XCTAssertEqual(first.first?.planType, "pro")
        XCTAssertNil(first.first?.membershipExpiresAt)
        XCTAssertEqual(first.first?.secondaryUsedPercent, 41)
        XCTAssertEqual(first.first?.secondaryWindowMinutes, 10_080)
        XCTAssertEqual(first.first?.primaryResetsAt, Date(timeIntervalSince1970: 1_776_409_393))
        XCTAssertEqual(cursorAfterFirst, Int64(try Data(contentsOf: session).count))
        XCTAssertEqual(second, [])
    }

    func testReadsMembershipExpirationFromRateLimits() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"limit_id":"codex","plan_type":"pro","membership_expires_at":1779000000,"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
                """,
                """
                {"timestamp":"2026-05-06T03:31:00Z","rate_limits":{"limit_id":"codex","plan_type":"team","subscription_expires_at":"2026-06-01T00:00:00Z","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":9.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: session
        )
        let reader = RateLimitReader(paths: paths, cursorStore: ParseCursorStore(paths: paths))

        let observations = try reader.readNewObservations()

        XCTAssertEqual(observations.map(\.membershipExpiresAt), [
            Date(timeIntervalSince1970: 1_779_000_000),
            ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")
        ])
    }

    func testMalformedLineBeforeValidRateLimitIsSkippedAndCursorAdvances() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                "{not-json",
                "{\"timestamp\":\"2026-05-06T03:29:00Z\",\"message\":\"no rate limit here\"}",
                """
                {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: session
        )
        let cursorStore = ParseCursorStore(paths: paths)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore)

        let observations = try reader.readNewObservations()
        let cursor = try cursorStore.load().offset(for: session)

        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?.primaryUsedPercent, 82)
        XCTAssertEqual(cursor, Int64(try Data(contentsOf: session).count))
    }

    func testReadsRateLimitsFromPayloadTokenCountEvent() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":96.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":30.0,"window_minutes":10080,"resets_at":1776937959}}}}
                """
            ],
            to: session
        )
        let reader = RateLimitReader(paths: paths, cursorStore: ParseCursorStore(paths: paths))

        let observations = try reader.readNewObservations()

        XCTAssertEqual(observations.map(\.primaryUsedPercent), [96])
        XCTAssertEqual(observations.first?.secondaryUsedPercent, 30)
    }

    func testReadsRateLimitsFromPayloadInfoTokenCountEvent() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":41170568},"rate_limits":{"limit_id":"codex","primary":{"used_percent":41.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":22.0,"window_minutes":10080,"resets_at":1776937959}}}}}
                """
            ],
            to: session
        )
        let reader = RateLimitReader(paths: paths, cursorStore: ParseCursorStore(paths: paths))

        let observations = try reader.readNewObservations()

        XCTAssertEqual(observations.map(\.primaryUsedPercent), [41])
        XCTAssertEqual(observations.first?.secondaryUsedPercent, 22)
    }

    func testCursorResetsWhenSessionFileShrinks() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: session
        )
        let cursorStore = ParseCursorStore(paths: paths)
        var staleCursor = ParseCursorState()
        staleCursor.setOffset(10_000, for: session)
        try cursorStore.save(staleCursor)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore)

        let observations = try reader.readNewObservations()
        let cursor = try cursorStore.load().offset(for: session)

        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?.primaryUsedPercent, 82)
        XCTAssertEqual(cursor, Int64(try Data(contentsOf: session).count))
    }

    func testMissingSessionFileCursorIsPruned() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        let missingSession = paths.codexHome.appendingPathComponent("sessions/missing.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: session
        )
        let cursorStore = ParseCursorStore(paths: paths)
        var cursorState = ParseCursorState()
        cursorState.setOffset(0, for: session)
        cursorState.setOffset(20, for: missingSession)
        try cursorStore.save(cursorState)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore)

        _ = try reader.readNewObservations()
        let updatedState = try cursorStore.load()

        XCTAssertGreaterThan(updatedState.offset(for: session), 0)
        XCTAssertEqual(updatedState.offset(for: missingSession), 0)
    }

    func testReadRangeIsBoundedToProvidedFileSize() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        let firstLine = """
        {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
        """
        let secondLine = """
        {"timestamp":"2026-05-06T03:31:00Z","rate_limits":{"primary":{"used_percent":83.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1776937959}}}
        """
        try writeJSONLLines([firstLine, secondLine], to: session)
        let firstLineByteCount = Int64((firstLine + "\n").data(using: .utf8)!.count)

        let observations = try RateLimitReader.readObservations(
            from: session,
            offset: 0,
            byteCount: firstLineByteCount
        )

        XCTAssertEqual(observations.map(\.primaryUsedPercent), [82])
    }

    func testLargeUnreadSessionStartsNearTailAndAdvancesCursor() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        let oldLine = """
        {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":11.0,"window_minutes":10080,"resets_at":1776937959}}}
        """
        let tailLine = """
        {"timestamp":"2026-05-06T03:35:00Z","rate_limits":{"primary":{"used_percent":90.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":91.0,"window_minutes":10080,"resets_at":1776937959}}}
        """
        let padding = (0..<40)
            .map { #"{"timestamp":"2026-05-06T03:31:00Z","message":"padding-\#($0)-abcdefghijklmnopqrstuvwxyz"}"# }
            .joined(separator: "\n")
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((oldLine + "\n" + padding + "\n" + tailLine + "\n").utf8).write(to: session)
        let cursorStore = ParseCursorStore(paths: paths)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore, maxReadBytesPerFile: 512)

        let observations = try reader.readNewObservations()
        let cursor = try cursorStore.load().offset(for: session)

        XCTAssertEqual(observations.map(\.primaryUsedPercent), [90])
        XCTAssertEqual(cursor, Int64(try Data(contentsOf: session).count))
    }

    func testPartialFinalLineIsReadAfterItCompletes() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let session = paths.codexHome.appendingPathComponent("sessions/2026/05/06/session.jsonl")
        let completeLine = """
        {"timestamp":"2026-05-06T03:30:00Z","rate_limits":{"primary":{"used_percent":82.0,"window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1776937959}}}
        """
        let partialLine = #"{"timestamp":"2026-05-06T03:31:00Z","rate_limits":{"primary":{"used_percent":83.0"#
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((completeLine + "\n" + partialLine).utf8).write(to: session)
        let cursorStore = ParseCursorStore(paths: paths)
        let reader = RateLimitReader(paths: paths, cursorStore: cursorStore)

        let first = try reader.readNewObservations()
        let cursorAfterPartial = try cursorStore.load().offset(for: session)
        let completedLineTail = #","window_minutes":300,"resets_at":1776409393},"secondary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1776937959}}}"# + "\n"
        let handle = try FileHandle(forWritingTo: session)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(completedLineTail.utf8))

        let second = try reader.readNewObservations()

        XCTAssertEqual(first.map(\.primaryUsedPercent), [82])
        XCTAssertEqual(cursorAfterPartial, Int64((completeLine + "\n").utf8.count))
        XCTAssertEqual(second.map(\.primaryUsedPercent), [83])
    }

    func testArchivedSessionsAreScanned() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CodixxPaths(home: home)
        let archived = paths.codexHome.appendingPathComponent("archived_sessions/archive.jsonl")
        try writeJSONLLines(
            [
                """
                {"timestamp":"2026-05-06T04:00:00Z","rate_limits":{"primary":{"used_percent":50.0,"window_minutes":300,"resets_at":1776411193},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1776937959}}}
                """
            ],
            to: archived
        )
        let reader = RateLimitReader(paths: paths, cursorStore: ParseCursorStore(paths: paths))

        let observations = try reader.readNewObservations()

        XCTAssertEqual(observations.map(\.sourceFile), [archived.resolvingSymlinksInPath().path])
        XCTAssertEqual(observations.first?.primaryUsedPercent, 50)
    }

    func testObservationCanConvertToAccountQuotaState() throws {
        let observation = RateLimitObservation(
            planType: "pro",
            primaryUsedPercent: 82,
            primaryWindowMinutes: 300,
            primaryResetsAt: Date(timeIntervalSince1970: 1_776_409_393),
            secondaryUsedPercent: 41,
            secondaryWindowMinutes: 10_080,
            secondaryResetsAt: Date(timeIntervalSince1970: 1_776_937_959),
            observedAt: Date(timeIntervalSince1970: 1_777_000_000),
            sourceFile: "/tmp/session.jsonl"
        )

        let state = observation.accountQuotaState(accountId: "account-1", alias: "Main", now: observation.observedAt)

        XCTAssertEqual(state.accountId, "account-1")
        XCTAssertEqual(state.alias, "Main")
        XCTAssertEqual(state.planType, "pro")
        XCTAssertEqual(state.primaryUsedPercent, 82)
        XCTAssertEqual(state.confidence, .fresh)
    }

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeJSONLLines(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: url)
    }
}
