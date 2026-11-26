import Foundation
import Testing
@testable import Cicada

@MainActor @Suite struct SettingsTests {
    /// 字幕条默认还是深色半透明条，纸条只是可选（DESIGN.md › 浮窗规则）。
    @Test func subtitleSkinDefaultsToDark() {
        UserDefaults.standard.removeObject(forKey: AppSettings.subtitleSkinKey)
        #expect(AppSettings().subtitleSkin == "dark")
    }
}
