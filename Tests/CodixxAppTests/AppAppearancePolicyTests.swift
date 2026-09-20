import AppKit
import SwiftUI
import XCTest
@testable import CodixxApp

/// 覆盖「Codixx 只做亮色」这条策略。
///
/// 背景：macOS 默认让 App 跟随系统外观，而 Codixx 从没做过暗色适配。
/// 系统切到深色时用户看到的是一个没调过的、发灰发糊的暗色版，所以显式钉亮色。
@MainActor
final class AppAppearancePolicyTests: XCTestCase {
    private var originalAppearance: NSAppearance?

    override func setUp() {
        super.setUp()
        originalAppearance = NSApplication.shared.appearance
    }

    override func tearDown() {
        NSApplication.shared.appearance = originalAppearance
        super.tearDown()
    }

    /// 系统里必须真的存在 `.aqua`，否则钉了个 nil 就等于没钉。
    func testPinnedAppearanceResolves() {
        XCTAssertEqual(AppAppearancePolicy.pinnedAppearanceName, .aqua)
        XCTAssertNotNil(AppAppearancePolicy.pinnedAppearance)
    }

    /// AppKit 侧和 SwiftUI 侧必须是同一个决定的两面 —— 两边不一致会出现
    /// 「背景按亮色解析、文字按暗色解析」的自相矛盾渲染。
    func testPinnedColorSchemeMatchesPinnedAppearance() {
        XCTAssertEqual(AppAppearancePolicy.pinnedAppearanceName, .aqua)
        XCTAssertEqual(AppAppearancePolicy.pinnedColorScheme, .light)
    }

    /// `apply()` 要真的把 App 级外观改掉。
    func testApplyPinsApplicationAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        AppAppearancePolicy.apply()

        XCTAssertEqual(NSApplication.shared.appearance?.name, .aqua)
    }

    /// 钉住之后，SwiftUI 的语义色必须按亮色解析。
    ///
    /// 注意：不要在测试进程里创建 `NSWindow` 再读 `effectiveAppearance` ——
    /// 无窗口服务器时会 SIGSEGV。这里改用 `ImageRenderer` 直接渲染取样。
    func testAppearanceOverridesInheritedDarkEnvironmentForSemanticColors() throws {
        // 模拟宿主传入深色环境，实际内容必须仍按亮色解析。
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var sample: (r: Int, g: Int, b: Int)?
        dark.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(
                content: Text("M")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 60, height: 60)
                    .background(Color.white)
                    .codixxAppearance()
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff)
            else { return }
            // 采样字形内部的像素：亮色方案下 .primary 是深色，暗色方案下是近白
            var darkest = (r: 255, g: 255, b: 255)
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let r = Int((c.redComponent * 255).rounded())
                    let g = Int((c.greenComponent * 255).rounded())
                    let b = Int((c.blueComponent * 255).rounded())
                    if r + g + b < darkest.r + darkest.g + darkest.b {
                        darkest = (r, g, b)
                    }
                }
            }
            sample = darkest
        }

        let darkest = try XCTUnwrap(sample, "renderer produced no image")
        // 亮色方案：文字是近黑；若没生效会是近白（>200）
        XCTAssertLessThan(darkest.r, 120, "expected dark text under pinned light scheme, got \(darkest)")
        XCTAssertLessThan(darkest.g, 120, "expected dark text under pinned light scheme, got \(darkest)")
        XCTAssertLessThan(darkest.b, 120, "expected dark text under pinned light scheme, got \(darkest)")
    }

    /// `NSPopover` 不是 `NSWindow`，但它同样要钉 —— 主界面就住在 popover 里。
    func testApplyPinsPopoverAppearance() {
        let popover = NSPopover()

        AppAppearancePolicy.apply(to: popover)

        XCTAssertEqual(popover.appearance?.name, .aqua)
    }

    /// 各面板（添加账号 / 编辑账号 / 退出确认）也必须钉住，
    /// 否则会出现「popover 是亮的、弹窗还是暗的」半吊子状态。
    func testApplyPinsPanelAppearance() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        AppAppearancePolicy.apply(to: panel)

        XCTAssertEqual(panel.appearance?.name, .aqua)
        XCTAssertEqual(panel.effectiveAppearance.name, .aqua)
    }

    /// 传 nil 不能崩 —— 调用方用的是可选的 `presentationParentWindow`。
    func testApplyAcceptsNilTarget() {
        AppAppearancePolicy.apply(to: nil)
    }

    /// 即使 App 级外观被别处改成深色，显式钉过的面板也要保持亮色。
    func testPanelAppearanceSurvivesApplicationAppearanceChange() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        AppAppearancePolicy.apply(to: panel)

        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        XCTAssertEqual(panel.effectiveAppearance.name, .aqua)
    }
}
