import AppKit
import XCTest
@testable import CodixxApp

@MainActor
final class ConfirmationDialogPresentationTests: XCTestCase {
    func testPopoverPanelPresentationAttachesAboveParentWindow() {
        let parent = NSWindow(
            contentRect: NSRect(x: 120, y: 180, width: 560, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.level = .floating
        parent.isReleasedWhenClosed = false
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        PopoverPanelPresentation.prepare(panel, parent: parent)
        defer {
            panel.parent?.removeChildWindow(panel)
            panel.close()
            parent.close()
        }

        XCTAssertTrue(parent.childWindows?.contains(where: { $0 === panel }) == true)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, parent.frame.minX - 1)
        XCTAssertLessThanOrEqual(panel.frame.maxX, parent.frame.maxX + 1)
        XCTAssertLessThanOrEqual(panel.frame.maxY, parent.frame.maxY + 1)
    }

    func testConfirmationDialogAttachesAboveParentWindow() {
        let parent = NSWindow(
            contentRect: NSRect(x: 120, y: 180, width: 560, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.level = .floating
        parent.isReleasedWhenClosed = false
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        IconlessConfirmationDialog.prepareForPresentation(panel, parent: parent)
        defer {
            panel.parent?.removeChildWindow(panel)
            panel.close()
            parent.close()
        }

        XCTAssertTrue(parent.childWindows?.contains(where: { $0 === panel }) == true)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, parent.frame.minX - 1)
        XCTAssertLessThanOrEqual(panel.frame.maxX, parent.frame.maxX + 1)
        XCTAssertLessThanOrEqual(panel.frame.maxY, parent.frame.maxY + 1)
    }

    func testConfirmationDialogFallsBackToPopoverLevelWhenNoParentWindowExists() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        IconlessConfirmationDialog.prepareForPresentation(panel, parent: nil)
        defer { panel.close() }

        XCTAssertNil(panel.parent)
        XCTAssertEqual(panel.level.rawValue, PopoverPanelPresentation.minimumAttachedLevel.rawValue)
    }

    func testModalPresentationRestoresLevelAbovePopoverDuringModalLoop() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        defer { panel.close() }

        DispatchQueue.main.async {
            DispatchQueue.main.async {
                XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
                NSApplication.shared.stopModal(withCode: .OK)
            }
        }

        let response = PopoverPanelPresentation.runModal(panel, parent: nil)

        XCTAssertEqual(response, .OK)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
    }
}
