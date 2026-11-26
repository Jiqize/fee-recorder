import SwiftUI

// 第四轮（样稿 round4-corners.html）：把上游留下的圆角白卡、灰底小标签、圆角输入框、胶囊 toast
// 换成纸上的东西。各界面只用这里的零件，不再各画各的圆角框。

/// 贴上去的便签：黄 = 提醒，粉 = 要你处理，绿 = 好消息。
enum SlipKind {
    case note, attention, good

    var color: Color {
        switch self {
        case .note: Palette.stickyYellow
        case .attention: Palette.stickyPink
        case .good: Palette.stickyGreen
        }
    }

    var tape: TapeStyle {
        switch self {
        case .note: .kraft
        case .attention: .pinkDots
        case .good: .greenCheck
        }
    }
}

private struct SlipBackground: ViewModifier {
    let kind: SlipKind
    @Environment(\.decor) private var decor
    func body(content: Content) -> some View {
        content
            .background(Rectangle().fill(kind.color))
            // 浮窗（最低装饰）里只留颜色，不贴胶带、不投影
            .overlay(alignment: .top) { if decor >= .low { Tape(style: kind.tape, width: 56).offset(y: -8) } }
            .modifier(SlipShadow(on: decor >= .low))
    }
}

private struct SlipShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.paperShadow() } else { content }
    }
}

extension View {
    /// 方角便签底 + 顶上一截胶带 + 纸的阴影（只换底，不加内边距）。
    func slipBackground(_ kind: SlipKind = .note) -> some View { modifier(SlipBackground(kind: kind)) }

    /// 白索引卡底：标题下一道红线、下面蓝横线（分享、引导里的步骤卡）。
    func indexCardBackground(titleHeight: CGFloat = 44) -> some View {
        background(IndexCard(titleHeight: titleHeight)).paperShadow(deeper: true)
    }
}

/// 只有一条下划线的输入框（像在横线上写字），代替系统的圆角框。
struct PaperFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 2).padding(.vertical, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink.opacity(0.8)).frame(height: 1.2) }
    }
}

extension TextFieldStyle where Self == PaperFieldStyle {
    static var paper: PaperFieldStyle { PaperFieldStyle() }
}

/// 挂在纸边的牛皮纸吊牌（底部提示：已改成 Mia · 撤销、回到正在播放）。
struct KraftLabel<Content: View>: View {
    var color: Color = Palette.kraft
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.paper).frame(width: 6, height: 6)
            content
        }
        .font(.fee(.bodySecondary)).foregroundStyle(Palette.ink)
        .padding(.leading, 14).padding(.trailing, 16).frame(height: 32)
        .background(TagShape().fill(color))
        .paperShadow(deeper: true)
    }
}

// MARK: 全角标点收紧

/// 霞鹜文楷等宽版里全角标点占一整格，「你好，我是菲比」看起来隔了一大格。在逗号、句号、顿号这些后面
/// 收一点字距（约 0.4 个字宽），读起来像正常排版。只改显示，不改文字本身。
enum CJKPunct {
    static let marks: Set<Character> = ["，", "。", "、", "；", "：", "！", "？"]

    static func tightened(_ s: AttributedString, size: CGFloat = 14) -> AttributedString {
        var out = s
        var i = out.startIndex
        while i < out.endIndex {
            let next = out.index(afterCharacter: i)
            // 句末的标点后面没有字，不用收
            if marks.contains(out.characters[i]), next < out.endIndex {
                out[i..<next].kern = -size * 0.4
            }
            i = next
        }
        return out
    }

    static func tightened(_ s: String, size: CGFloat = 14) -> AttributedString { tightened(AttributedString(s), size: size) }
}
