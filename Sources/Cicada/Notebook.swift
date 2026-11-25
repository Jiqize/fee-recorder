import SwiftUI

// 主窗口详情页的「纸上手记」排版件（DESIGN.md › 主窗口，样稿 docs/design/mockups/main-window.html）：
// 一整张横线纸，内容列 = 红线右侧 52pt 角色栏 + 正文；页边栏、页脚也都是纸上的字。

enum NotebookMetrics {
    /// 红线右侧放小角色、编号、说话人头像的一栏。
    static let gutter: CGFloat = 52
    static let marginColumn: CGFloat = 262
    static let trailing: CGFloat = 28
}

/// 角色栏 + 正文 + 行尾（时间点）。角色栏和行尾都按第一行对齐。
struct GutterRow<Gutter: View, Content: View, Trailing: View>: View {
    @ViewBuilder var gutter: Gutter
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter.frame(width: NotebookMetrics.gutter, alignment: .trailing).frame(minHeight: PaperMetrics.pitch)
            content.frame(maxWidth: .infinity, alignment: .leading)
            trailing.padding(.leading, 12)
        }
    }
}

extension GutterRow where Trailing == EmptyView {
    init(@ViewBuilder gutter: () -> Gutter, @ViewBuilder content: () -> Content) {
        self.init(gutter: gutter, content: content, trailing: { EmptyView() })
    }
}

extension GutterRow where Gutter == Color, Trailing == EmptyView {
    /// 角色栏空着的一行。
    init(@ViewBuilder content: () -> Content) {
        self.init(gutter: { Color.clear }, content: content, trailing: { EmptyView() })
    }
}

/// 只有横线（不填底色），跟着内容一起滚动；内容不够长时往下多画一截，铺满可见区域。
struct RuledLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = PaperMetrics.pitch
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(Palette.rule))
                y += PaperMetrics.pitch
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// 给滚动内容垫上横线：从内容顶部起每 24pt 一条，比内容多画 2000pt。
    func ruledBackground() -> some View {
        background(alignment: .top) {
            GeometryReader { g in RuledLines().frame(height: g.size.height + 2000) }
        }
    }
}

/// 页眉里的「纪要」「文字记录」：普通的字，当前那个加粗，下面一道红铅笔波浪线。
struct NotebookTab: View {
    let title: String
    let on: Bool
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.fee(.body, strong: on)).foregroundStyle(on ? Palette.ink : Palette.secondary)
                if let count { Text("\(count)").font(.fee(.caption)).foregroundStyle(Palette.tertiary) }
            }
            .frame(height: PaperMetrics.pitch)
            .overlay(alignment: .bottom) {
                if on {
                    SquiggleShape().stroke(Palette.link, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(height: 5).padding(.horizontal, -4).offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 一道随手画的波浪下划线。
private struct SquiggleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + 1))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.35, y: r.midY), control: CGPoint(x: r.minX + r.width * 0.18, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.7, y: r.midY + 0.5), control: CGPoint(x: r.minX + r.width * 0.52, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY - 0.5), control: CGPoint(x: r.minX + r.width * 0.86, y: r.minY))
        return p
    }
}

/// 页眉右边「分享…」「导出…」这类工具：普通的字，下面一道虚线。
struct NotebookWord<Label: View>: View {
    var on = true
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.fee(.body))
            .foregroundStyle(on ? Palette.secondary : Palette.placeholder)
            .overlay(alignment: .bottom) {
                Line().stroke(on ? Palette.placeholder : .clear, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(height: 1).offset(y: 1)
            }
            .frame(height: PaperMetrics.pitch)
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// 小节标题：字 + 一道波浪线，占一格。
struct NotebookHeading: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.fee(.section)).foregroundStyle(Palette.ink)
            WavyRule(width: 70)
        }
        .frame(height: PaperMetrics.pitch)
    }
}

/// 角色栏里的红铅笔编号（议题 01、结论 1）。
struct GutterNumber: View {
    let text: String
    var faint = false

    var body: some View {
        Text(text).font(.fee(.meta, strong: true)).foregroundStyle(faint ? Palette.secondary : Palette.link)
            .padding(.trailing, 10).frame(height: PaperMetrics.pitch)
    }
}

/// 文字记录里说话人的头像：说话人颜色的手写圆圈 + 首字（以后可换成插画）。
struct SpeakerAvatar: View {
    let text: String
    let color: Color

    var body: some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.fee(.label, strong: true)).foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Palette.paper))
            .overlay(Circle().stroke(color, lineWidth: 1.6))
            .rotationEffect(.degrees(-6))
            .frame(height: PaperMetrics.pitch)
            .padding(.trailing, 14)
    }
}

extension View {
    /// 详情页的正文列：从红线开始，顶上空一格，下面垫横线。
    func notebookColumn() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, PaperMetrics.marginX).padding(.trailing, NotebookMetrics.trailing)
            .padding(.top, PaperMetrics.pitch).padding(.bottom, PaperMetrics.pitch * 2)
            .ruledBackground()
    }
}

/// 把高度不定的块（鱼骨图、编辑框）向上取整到横线间距的整数倍，下面的字还落在线上。
struct RuleSnap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: s.width, height: PaperMetrics.snap(s.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let h = subviews.first?.sizeThatFits(proposal).height ?? 0
        // 居中放，上下各留一半空
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.minY + (bounds.height - h) / 2),
                              proposal: ProposedViewSize(width: bounds.width, height: h))
    }
}

extension View {
    func snapToRules() -> some View { RuleSnap { self } }
}

// MARK: 页边栏

/// 页边栏：日期 → 拍立得里的菲比 → 一句状态 → 「本场」划记 → 粉色待办便利贴 → 底部录音铅笔。
struct NotebookMarginColumn: View {
    let date: String
    let mood: FeebeeMood
    let stats: [(label: String, count: Int)]
    let todos: [NoteItem]
    /// 点一条待办：打开它的编辑（编号从 0 起，按结论之后数）。
    var openTodo: ((Int) -> Void)? = nil
    /// 录音：已播放 / 总长；没有录音为 nil。
    var recording: (position: Double, total: Double)? = nil
    var playRecording: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(date).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                .frame(height: PaperMetrics.pitch).padding(.top, 8)
            Polaroid(caption: L("菲比")) { FeebeeView(mood: mood, size: 144) }
                .frame(width: 160).padding(.top, 10)
            Text(mood.status).font(.fee(.body)).foregroundStyle(Palette.ink)
                .frame(height: PaperMetrics.pitch).padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("本场").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    WavyRule(width: 60)
                }
                .frame(height: PaperMetrics.pitch)
                ForEach(stats, id: \.label) { row in
                    HStack(spacing: 0) {
                        Text(row.label).font(.fee(.bodySecondary)).foregroundStyle(Palette.ink)
                            .fixedSize().frame(minWidth: uiIsChinese ? 64 : 96, alignment: .leading).padding(.trailing, 6)
                        TallyMark(count: min(row.count, 10))
                        Spacer(minLength: 8)
                        Text("\(row.count)").font(.fee(.meta)).foregroundStyle(Palette.ink)
                    }
                    .frame(height: PaperMetrics.pitch)
                }
            }
            .padding(.leading, 18).padding(.trailing, 22).padding(.top, 24)

            if !todos.isEmpty {
                StickyNote(color: Palette.stickyPink, tape: .pinkDots, tilt: 0.8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("待办").font(.fee(.section)).foregroundStyle(Palette.link)
                        ForEach(Array(todos.enumerated()), id: \.offset) { i, item in
                            Button { openTodo?(i) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "square").font(.icon(11)).foregroundStyle(Palette.body)
                                    (Text(item.text).foregroundStyle(Palette.ink)
                                     + Text(item.ownerShown.map { " · " + $0 } ?? "").font(.fee(.label)).foregroundStyle(Palette.secondary))
                                        .font(.fee(.bodySecondary))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(openTodo == nil)
                            .help(openTodo == nil ? "" : L("点一下修改"))
                        }
                    }
                }
                .padding(.leading, 16).padding(.trailing, 18).padding(.top, 26)
            }

            Spacer(minLength: 16)

            if let recording {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("录音").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text("\(TranscriptExport.clock(recording.position)) / \(TranscriptExport.clock(recording.total))")
                            .font(.fee(.meta)).foregroundStyle(Palette.ink)
                    }
                    Button { playRecording?() } label: {
                        PencilBar(fraction: recording.total > 0 ? recording.position / recording.total : 0)
                            .frame(height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(L("从这里接着听"))
                }
                .padding(.leading, 18).padding(.trailing, 22).padding(.bottom, 26)
            }
        }
        .frame(width: NotebookMetrics.marginColumn)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { RuledLines().padding(.top, 8) }
        .overlay(alignment: .leading) { Rectangle().fill(Palette.tertiary.opacity(0.35)).frame(width: 1) }
    }
}

/// 一支铅笔当进度条：笔身是已播放的部分，后面虚线是剩下的。
struct PencilBar: View {
    let fraction: Double

    var body: some View {
        Canvas { ctx, size in
            let h = size.height - 4, y = 2.0
            let tip = 16.0, eraser = 8.0
            let body = (size.width - tip - eraser) * min(1, max(0, fraction))
            var cone = Path()
            cone.move(to: CGPoint(x: 0, y: y + h / 2))
            cone.addLine(to: CGPoint(x: tip, y: y))
            cone.addLine(to: CGPoint(x: tip, y: y + h))
            cone.closeSubpath()
            ctx.fill(cone, with: .color(Palette.kraft))
            ctx.stroke(cone, with: .color(Palette.ink), lineWidth: 1)
            ctx.fill(Path(CGRect(x: 0, y: y + h / 2 - 2, width: 5, height: 4)), with: .color(Palette.ink))
            let barrel = CGRect(x: tip, y: y, width: body, height: h)
            ctx.fill(Path(barrel), with: .color(Palette.hex(0xF2C94C)))
            ctx.stroke(Path(barrel), with: .color(Palette.ink), lineWidth: 1)
            let rest = CGRect(x: tip + body, y: y, width: size.width - tip - eraser - body, height: h)
            ctx.stroke(Path(rest), with: .color(Palette.placeholder), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let end = CGRect(x: size.width - eraser, y: y, width: eraser, height: h)
            ctx.fill(Path(roundedRect: end, cornerRadius: 2), with: .color(Palette.hex(0xF4A3A8)))
            ctx.stroke(Path(roundedRect: end, cornerRadius: 2), with: .color(Palette.ink), lineWidth: 1)
        }
    }
}

// MARK: 页脚

/// 纸底部的三行：状态（红铅笔）→ 红线下的搜索行 → 细线下的蓝色快捷键提示。
struct NotebookFooter: View {
    let status: String
    var detail: String = ""
    var done = false
    @Binding var query: String
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text((done ? "✓ " : "* ") + status).font(.fee(.body)).foregroundStyle(Palette.link)
                if !detail.isEmpty { Text("· " + detail).font(.fee(.meta)).foregroundStyle(Palette.tertiary) }
            }
            .frame(height: PaperMetrics.pitch)
            HStack(spacing: 8) {
                Text("›").font(.fee(.meta, strong: true)).foregroundStyle(Palette.ink)
                TextField(L("在这场会议里找…"), text: $query)
                    .textFieldStyle(.plain).focusEffectDisabled()
                    .font(.fee(.body)).foregroundStyle(Palette.ink)
                    .onSubmit(onSubmit)
            }
            .frame(height: 30)
            .overlay(alignment: .top) { Rectangle().fill(Palette.margin).frame(height: 1) }
            .padding(.top, 4)
            Text(L("⌘F 搜索 · ⌘R 开始听 · 点时间跳到原话 · 点纪要直接改"))
                .font(.fee(.bodySecondary)).foregroundStyle(Palette.inkBlue)
                .frame(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        }
        .padding(.leading, 18).padding(.trailing, NotebookMetrics.trailing)
    }
}
