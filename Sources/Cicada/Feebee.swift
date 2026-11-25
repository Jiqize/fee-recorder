import AppKit
import SwiftUI

/// 小蜜蜂菲比此刻的样子（DESIGN.md › 原创角色）：页眉和页边栏的拍立得都按它换图。
enum FeebeeMood: String, CaseIterable {
    case idle, listening, writing, done, error

    /// 出错只在会议进行中才算（回看旧会议时，别的请求失败与这场无关）；
    /// 正在写纪要优先于在听；写完是纪要定稿之后。
    static func of(live: Bool, notesState: NotesEngine.State, hasNotes: Bool, final: Bool) -> FeebeeMood {
        switch notesState {
        case .noKey, .invalidKey, .rateLimited, .unreachable, .failed:
            if live { return .error }
        case .updating: return .writing
        case .idle: break
        }
        if live { return .listening }
        if hasNotes && final { return .done }
        return .idle
    }

    var imageName: String { "feebee-\(rawValue)" }

    /// 拍立得下面的一句状态。
    var status: String {
        switch self {
        case .idle: L("在打盹")
        case .listening: L("正在听")
        case .writing: L("正在写纪要")
        case .done: L("把纪要写好了")
        case .error: L("出了点问题")
        }
    }
}

/// 菲比的插画（`Resources/illustrations/`，读 @2x 那张）；读不到就画一个占位圆，不崩溃。
struct FeebeeView: View {
    let mood: FeebeeMood
    var size: CGFloat = 160

    var body: some View {
        if let image = Self.image(mood) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel(mood.status)
        } else {
            Circle().fill(Palette.paperShade).frame(width: size * 0.8, height: size * 0.8).frame(width: size, height: size)
        }
    }

    @MainActor private static var cache: [FeebeeMood: NSImage] = [:]

    @MainActor static func image(_ mood: FeebeeMood) -> NSImage? {
        if let hit = cache[mood] { return hit }
        guard let url = Bundle.main.url(forResource: mood.imageName + "@2x", withExtension: "png", subdirectory: "illustrations"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[mood] = image
        return image
    }
}
