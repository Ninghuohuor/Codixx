import AppKit
import Darwin
import SwiftUI
import XCTest
import CodixxCore
@testable import CodixxApp

/// Opt-in, isolated UI workload for comparing the same refreshes across builds.
/// Does not start the app lifecycle, query accounts, or touch the user's data.
@MainActor
final class MemoryWorkloadTests: XCTestCase {
    func testRepeatedLogReadsAndAppends() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["CODIXX_LOG_PROBE_OUTPUT"],
              let source = environment["CODIXX_LOG_PROBE_SOURCE"] else {
            throw XCTSkip("Set CODIXX_LOG_PROBE_OUTPUT and CODIXX_LOG_PROBE_SOURCE to run the log workload")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CodixxPaths(home: directory)
        try paths.createApplicationSupportDirectories()
        for url in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: source), includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("app_activity") && url.pathExtension == "jsonl" {
            try FileManager.default.copyItem(at: url, to: paths.applicationSupport.appendingPathComponent(url.lastPathComponent))
        }
        let now = Date()
        let log = AppActivityLog(paths: paths, retention: .init(now: { now }))
        let originalCount = try log.loadEvents().count
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            try autoreleasepool { XCTAssertEqual(try log.loadEvents().count, originalCount) }
        }
        let readSeconds = ProcessInfo.processInfo.systemUptime - start
        let appendStart = ProcessInfo.processInfo.systemUptime
        var identityChanges = 0
        var identity = try FileManager.default.attributesOfItem(atPath: paths.appActivityJSONL.path)[.systemFileNumber] as? NSNumber
        for index in 0..<20 {
            try autoreleasepool {
                try log.append(AppLogEvent(timestamp: now.addingTimeInterval(Double(index)), kind: .apiBalanceRefreshed, accountAlias: "Memory test"))
                XCTAssertEqual(try log.loadEvents().count, originalCount + index + 1)
                let next = try FileManager.default.attributesOfItem(atPath: paths.appActivityJSONL.path)[.systemFileNumber] as? NSNumber
                if next != identity { identityChanges += 1 }
                identity = next
            }
        }
        let report: [String: Any] = [
            "historical_events": originalCount, "unchanged_loads": 100,
            "unchanged_load_seconds": readSeconds, "appended_events": 20,
            "append_and_reload_seconds": ProcessInfo.processInfo.systemUptime - appendStart,
            "file_replacements": identityChanges
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output))
    }

    func testRepeatedDashboardRefreshes() throws {
        guard let output = ProcessInfo.processInfo.environment["CODIXX_MEMORY_PROBE_OUTPUT"] else {
            throw XCTSkip("Set CODIXX_MEMORY_PROBE_OUTPUT to run the UI memory workload")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        AppAppearancePolicy.apply()
        let state = AppState(paths: CodixxPaths(home: directory))
        let host = NSHostingController(rootView: DashboardView(state: state))
        let window = NSPanel(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 560, height: 520),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        host.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        var samples: [[String: Double]] = []
        func sample(_ iteration: Int) {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            var malloc = malloc_statistics_t()
            malloc_zone_statistics(nil, &malloc)
            samples.append([
                "iteration": Double(iteration),
                "physical_footprint_mib": result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1,
                "allocated_mib": Double(malloc.size_in_use) / 1_048_576,
                "allocated_blocks": Double(malloc.blocks_in_use)
            ])
        }
        sample(0)
        for iteration in 1...6_000 {
            autoreleasepool {
                state.errorMessage = "Memory workload \(iteration)"
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
                host.view.layoutSubtreeIfNeeded()
                host.view.displayIfNeeded()
            }
            if iteration % 1_000 == 0 { sample(iteration) }
        }
        state.errorMessage = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        sample(6_001)
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output))
        XCTAssertEqual(samples.count, 8)
        if let maximum = ProcessInfo.processInfo.environment["CODIXX_MEMORY_MAX_GROWTH_MIB"].flatMap(Double.init) {
            XCTAssertLessThan(samples.last!["allocated_mib"]! - samples[1]["allocated_mib"]!, maximum)
        }
    }
}
