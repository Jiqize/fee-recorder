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
    /// 每种状态一个很轻的小动作（第六轮样稿 ②）；截图、导出图片时关掉。
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let image = Self.image(mood) {
            let still = Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            Group {
                if animated && !reduceMotion {
                    FeebeeMotion(mood: mood, size: size) { still }.id(mood)
                } else {
                    still
                }
            }
            .accessibilityLabel(mood.status)
        } else {
            Circle().fill(Palette.paperShade).frame(width: size * 0.8, height: size * 0.8).frame(width: size, height: size)
        }
    }

    @MainActor static func image(_ mood: FeebeeMood) -> NSImage? { Illustration.image(mood.imageName) }
}

/// `Resources/illustrations/` 里的插画（读 @2x 那张，读过就缓存）。
enum Illustration {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name + "@2x", withExtension: "png", subdirectory: "illustrations"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    /// 说话人头像：「你」是蓝圆珠笔，说话人 1–4 是菲比的花园朋友（蜗牛、蝴蝶、瓢虫、蚂蚁），之后循环。
    static func speaker(_ number: Int?, me: Bool) -> String? {
        if me { return "you" }
        guard let number else { return nil }
        return "speaker-\((max(1, number) - 1) % 4 + 1)"
    }
}

/// 菲比的小动作：打盹一起一伏、头上飘 z；在听耳机旁声波一闪一闪；在写左右轻摇；写好了跳一下；
/// 出了问题摇一下头。幅度都很小，循环的 2 秒左右一次，交给 Core Animation，不逐帧重画。
private struct FeebeeMotion<Content: View>: View {
    let mood: FeebeeMood
    let size: CGFloat
    @ViewBuilder var content: Content
    @State private var on = false

    var body: some View {
        content
            .scaleEffect(mood == .idle && on ? 1.03 : 1, anchor: .bottom)
            .rotationEffect(.degrees(mood == .writing ? (on ? 3 : -3) : mood == .error ? (on ? 0 : -5) : 0))
            .offset(y: mood == .done && !on ? -size * 0.06 : 0)
            .overlay(alignment: .topLeading) {
                if mood == .idle {
                    Text(verbatim: "z").font(.fee(.label, strong: true)).foregroundStyle(Palette.tertiary)
                        .offset(x: size * 0.12, y: on ? -size * 0.08 : size * 0.06)
                        .opacity(on ? 0 : 0.8)
                }
            }
            .overlay(alignment: .trailing) {
                if mood == .listening {
                    Text(verbatim: ")))").font(.fee(.label, strong: true)).foregroundStyle(Palette.accent)
                        .opacity(on ? 0.9 : 0.2)
                        .offset(x: size * 0.04)
                }
            }
            .onAppear {
                switch mood {
                case .done:
                    // 写好的那一刻跳一下，之后不动
                    withAnimation(.spring(duration: 0.45, bounce: 0.5)) { on = true }
                case .error:
                    withAnimation(.spring(duration: 0.5, bounce: 0.7)) { on = true }
                case .idle:
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { on = true }
                case .listening:
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
                case .writing:
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
                }
            }
    }
}
