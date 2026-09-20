import AppKit
import SwiftUI

/// Codixx 只提供亮色外观。
///
/// macOS 10.14 起所有 App 默认跟随系统外观。Codixx 从来没有做过暗色适配
/// （卡片底一律用 `NSColor.controlBackgroundColor`，而它和
/// `windowBackgroundColor` 取值完全相同，叠在 `NSPopover` 的材质上会让暗色
/// 模式的层次整个反转），所以系统切到深色时，用户看到的是一个没调过的、
/// 发灰发糊的暗色版。
///
/// 与其让系统去渲染一个没人设计过的暗色版，不如显式钉死在亮色。
enum AppAppearancePolicy {
    /// 固定使用的外观。
    static let pinnedAppearanceName: NSAppearance.Name = .aqua

    /// SwiftUI 侧的对应值，和 `pinnedAppearanceName` 是同一个决定的两面。
    ///
    /// SwiftUI 的语义色走 `colorScheme` 环境解析，AppKit 的动态色走
    /// `NSAppearance` —— 两条路都要钉，否则会出现「背景按亮色解析、文字按
    /// 暗色解析」这种自相矛盾的渲染。
    static let pinnedColorScheme: ColorScheme = .light

    /// 解析出固定外观；系统里取不到时返回 `nil`（理论上不会发生）。
    static var pinnedAppearance: NSAppearance? {
        NSAppearance(named: pinnedAppearanceName)
    }

    /// 固定整个 App 的外观。
    ///
    /// 只设 `NSApplication.shared.appearance` 是不够保险的 —— SwiftUI 的 scene
    /// 装配时机可能晚于 `App.init()`，所以对 App 自己创建的每个 `NSWindow` /
    /// `NSPanel` / `NSPopover` 还要单独设一次（见各自的 `appearance` 赋值）。
    /// 两边都设，才能避免「popover 是亮的、弹窗还是暗的」这种半吊子状态。
    @MainActor
    static func apply() {
        NSApplication.shared.appearance = pinnedAppearance
    }

    /// 给单个 AppKit 容器钉外观。
    ///
    /// 取 `NSAppearanceCustomization` 而不是 `NSWindow`：`NSPopover` 不是窗口，
    /// 但同样需要钉住，用这个协议一个函数就能覆盖 `NSWindow` / `NSPanel` /
    /// `NSPopover` 三种容器。
    @MainActor
    static func apply(to target: (any NSAppearanceCustomization)?) {
        target?.appearance = pinnedAppearance
    }
}

extension View {
    /// AppKit hosting boundaries do not necessarily consume SwiftUI presentation
    /// preferences. Set the environment as well, including for standalone panels.
    func codixxAppearance() -> some View {
        self
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, AppAppearancePolicy.pinnedColorScheme)
            .preferredColorScheme(AppAppearancePolicy.pinnedColorScheme)
    }
}
