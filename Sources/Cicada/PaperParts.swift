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

// MARK: - 纸上的小零件（第四轮样稿 round4-corners ③ ⑦ ⑧，原在 SettingsWindow.swift）

/// 小橡皮章（同 `Tag`，能换颜色和字号）：细框、不填色、完整装饰下略歪。
struct StampLabel: View {
    let text: String
    var color: Color = Palette.secondary
    var role: TypeRole = .label
    var body: some View {
        Text(text).font(.fee(role, strong: true)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(Rectangle().stroke(color, lineWidth: 1.2))
            .tilted(-2)
            .fixedSize()
    }
}

/// 检查结果、步骤的手画方框：做完是绿勾，失败是红框，进行中是小转圈，跳过是虚线框。
struct PaperCheck: View {
    enum Mark { case done, open, failed, warn, running, skipped }
    let mark: Mark
    var size: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if mark == .running {
                ProgressView().controlSize(.mini).frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: mark == .skipped ? [2, 2] : []))
                    .frame(width: size, height: size).rotationEffect(.degrees(-3))
                if mark == .done {
                    PencilTick().stroke(Palette.ok, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: size - 1, height: size + 1).offset(x: 2, y: -1)
                }
            }
        }
        .frame(width: size + 4, height: size + 4)
    }

    private var color: Color {
        switch mark {
        case .failed: Palette.error
        case .warn: Palette.warn
        case .skipped: Palette.placeholder
        default: Palette.body
        }
    }
}

/// 一笔铅笔勾（同待办方框里的勾）。
private struct PencilTick: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 1))
        return p
    }
}

/// 一道水平线（配虚线笔画用：下拉菜单下面的铅笔虚线）。
struct PencilLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// 步骤的红铅笔编号 1 2 3。
struct PencilNumber: View {
    let n: Int
    var body: some View {
        Text(verbatim: "\(n)").font(.fee(.body, strong: true)).foregroundStyle(Palette.link)
            .frame(width: 14, alignment: .center)
    }
}

/// 白索引卡（引导里的步骤卡）：标题写在第一格、下面一道红线，顶上一截牛皮纸胶带。
/// 没有标题时是一张素白卡（不画红线）。
struct StepIndexCard<Content: View>: View {
    var title: String? = nil
    var note: String? = nil
    /// 标题前的方框（已连接打勾）。
    var mark: PaperCheck.Mark? = nil
    /// 标题行右边的东西（按钮、遮住的 key）。
    var accessory: AnyView? = nil
    static var titleHeight: CGFloat { 44 }
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { header(title) }
            content
        }
        .padding(.horizontal, 20).padding(.top, title == nil ? 16 : 0).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if title != nil { IndexCard(titleHeight: Self.titleHeight) } else { Rectangle().fill(Palette.polaroid) } }
        .paperShadow(deeper: true)
        .overlay(alignment: .top) { Tape(style: .kraft, width: 64).offset(y: -8) }
        // 给胶带和阴影留出地方：放在滚动区顶上时不被裁掉
        .padding(.top, 14)
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: 8) {
            if let mark { PaperCheck(mark: mark) }
            Text(title).font(.fee(.section)).foregroundStyle(Palette.ink).lineLimit(1)
            if let note {
                // 英文长：最多折成两行，仍在标题格里
                Text(note).font(.fee(.label)).foregroundStyle(Palette.tertiary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let accessory { accessory }
        }
        .frame(height: Self.titleHeight)
    }
}
