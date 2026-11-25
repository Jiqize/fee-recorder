import SwiftUI

// 纸张风格的装饰组件（DESIGN.md › 纸张、组件）。界面只组合这里的组件，不在各视图里各画各的。
// 装饰强度由环境值 `decor` 决定：默认最弱（实时纪要窗那种素纸），主窗口、引导等在根视图上调高。

/// 装饰强度：minimal = 只换颜色和字体；low = 素纸；medium = 加纸纹；full = 横线、打孔、旋转、胶带全上。
enum Decor: Int, Comparable {
    case minimal, low, medium, full
    static func < (a: Decor, b: Decor) -> Bool { a.rawValue < b.rawValue }
}

private struct DecorKey: EnvironmentKey { static let defaultValue = Decor.minimal }
extension EnvironmentValues {
    var decor: Decor {
        get { self[DecorKey.self] }
        set { self[DecorKey.self] = newValue }
    }
}

extension View {
    func decor(_ level: Decor) -> some View { environment(\.decor, level) }
}

enum PaperMetrics {
    /// 横线间距：正文行高补到这个高度。
    static let pitch: CGFloat = 24
    /// 红色页边线离纸左边的距离；线左边是页边（时间戳、编号）。
    static let marginX: CGFloat = 64
    static let holeDiameter: CGFloat = 14
    static let holeCount = 3
    static let corkInset: CGFloat = 16
    static let sidebarWidth: CGFloat = 232
    static let marginColumnWidth: CGFloat = 220
    static let marginColumnBreakpoint: CGFloat = 1000
    static let gridPitch: CGFloat = 12

    static func lineSpacing(lineHeight: CGFloat, pitch: CGFloat = pitch) -> CGFloat { max(0, pitch - lineHeight) }
    static func lineSpacing(_ role: TypeRole) -> CGFloat { lineSpacing(lineHeight: FeeFonts.lineHeight(role)) }

    /// 向上取到横线间距的整数倍。
    static func snap(_ height: CGFloat) -> CGFloat { (height / pitch).rounded(.up) * pitch }

    static func showsMarginColumn(windowWidth: CGFloat) -> Bool { windowWidth >= marginColumnBreakpoint }
}

extension View {
    /// 字体 + 对齐横线的行距：每行正好占一格 24pt，行距一半放上面一半放下面，
    /// 所以多段文字上下叠放也还在格子里。
    func ruledText(_ role: TypeRole, strong: Bool = false) -> some View {
        let gap = PaperMetrics.lineSpacing(role)
        return font(.fee(role, strong: strong)).lineSpacing(gap).padding(.vertical, gap / 2)
    }

    /// 纸的阴影：y 2 / blur 8 / 12% #3A2A18。
    func paperShadow(deeper: Bool = false) -> some View {
        // 先合成一层再投影，阴影只落在纸的外轮廓上，不落在每个字上
        compositingGroup().shadow(color: Palette.paperShadow, radius: deeper ? 8 : 4, x: 0, y: deeper ? 4 : 2)
    }

    /// 只在完整装饰下旋转；静态角度，不加动画。
    func tilted(_ degrees: Double) -> some View { modifier(Tilt(degrees: degrees)) }

    /// 荧光笔：压在文字下面的一块 `mark`，两端略不齐。
    func highlighted() -> some View {
        background(alignment: .center) {
            HighlighterShape().fill(Palette.mark).padding(.horizontal, -2).padding(.vertical, 1)
        }
    }
}

private struct Tilt: ViewModifier {
    @Environment(\.decor) private var decor
    let degrees: Double
    func body(content: Content) -> some View { content.rotationEffect(.degrees(decor == .full ? degrees : 0)) }
}

/// 一个固定种子的伪随机序列：纸纹、软木斑点每次画出来都一样。
private struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 33) / Double(1 << 31)
    }
}

// MARK: 纸与板

/// 活页纸：`paper` 底 + 24pt 浅蓝横线 + 红页边线，可选左侧三个打孔。
/// `ruled: false` 时只留红线（行高对不齐的地方宁可没线）。装饰低于 full 时不画横线和打孔。
struct RuledPaper: View {
    var holes = false
    var ruled = true
    @Environment(\.decor) private var decor

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.paper))
            if decor >= .medium { grain(ctx, size) }
            guard decor == .full else { return }
            if ruled {
                var y = PaperMetrics.pitch
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(Palette.rule))
                    y += PaperMetrics.pitch
                }
            }
            ctx.fill(Path(CGRect(x: PaperMetrics.marginX - 0.5, y: 0, width: 1, height: size.height)), with: .color(Palette.margin))
            if holes {
                let d = PaperMetrics.holeDiameter
                for f: CGFloat in [0.15, 0.5, 0.85] {
                    let r = CGRect(x: 18 - d / 2, y: size.height * f - d / 2, width: d, height: d)
                    ctx.fill(Path(ellipseIn: r), with: .color(Palette.hole))
                    // 内阴影：上沿一圈更暗的弧，像孔的边
                    ctx.stroke(Path(ellipseIn: r.insetBy(dx: 0.75, dy: 0.75)).offsetBy(dx: 0, dy: 0.75),
                               with: .color(.black.opacity(0.35)), lineWidth: 1.5)
                }
            }
        }
    }

    /// 很淡的浅色纸纹，不透明度 ≤ 4%，不用深色噪点。
    private func grain(_ ctx: GraphicsContext, _ size: CGSize) {
        var rnd = Seeded(7)
        let count = Int(size.width * size.height / 90)
        for _ in 0..<min(count, 20_000) {
            let p = CGRect(x: rnd.next() * size.width, y: rnd.next() * size.height, width: 1.2, height: 1.2)
            ctx.fill(Path(ellipseIn: p), with: .color(Palette.kraft.opacity(0.04)))
        }
    }
}

/// 笔记页：活页纸 + 纸的阴影；内容放在上面。
struct NotebookPage<Content: View>: View {
    var holes = false
    var ruled = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RuledPaper(holes: holes, ruled: ruled))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .paperShadow()
    }
}

/// 软木板：`cork` 底 + 固定种子的深色斑点，不用图片。
struct CorkBoard: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.cork))
            var rnd = Seeded(42)
            let count = Int(size.width * size.height / 140)
            for _ in 0..<min(count, 30_000) {
                let s = 0.8 + rnd.next() * 2.2
                let p = CGRect(x: rnd.next() * size.width, y: rnd.next() * size.height, width: s, height: s * (0.6 + rnd.next() * 0.8))
                let light = rnd.next() > 0.6
                ctx.fill(Path(ellipseIn: p), with: .color(light ? Palette.kraft.opacity(0.35) : Palette.corkDeep.opacity(0.55)))
            }
        }
    }
}

/// 方格纸（鱼骨图底）。
struct GridPaper: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.paper))
            let step = PaperMetrics.gridPitch
            var x: CGFloat = 0
            while x <= size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(Palette.grid))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(Palette.grid))
                y += step
            }
        }
    }
}

// MARK: 贴在纸上的东西

enum TapeStyle { case kraft, pinkDots, greenCheck }

/// 一截半透明胶带，两端剪得不齐。最弱装饰下不画。
struct Tape: View {
    var style: TapeStyle = .kraft
    var width: CGFloat = 56
    @Environment(\.decor) private var decor

    var body: some View {
        if decor >= .low {
            TapeShape()
                .fill(color)
                .overlay { pattern.clipShape(TapeShape()) }
                .frame(width: width, height: 16)
        }
    }

    private var color: Color {
        switch style {
        case .kraft: Palette.tapeKraft
        case .pinkDots: Palette.tapePink
        case .greenCheck: Palette.tapeGreen
        }
    }

    @ViewBuilder private var pattern: some View {
        switch style {
        case .kraft: EmptyView()
        case .pinkDots:
            Canvas { ctx, size in
                var x: CGFloat = 4
                while x < size.width {
                    for y in [4.0, 11.0] {
                        ctx.fill(Path(ellipseIn: CGRect(x: x + (y > 5 ? 3.5 : 0), y: y - 1.2, width: 2.4, height: 2.4)),
                                 with: .color(Palette.paper.opacity(0.7)))
                    }
                    x += 7
                }
            }
        case .greenCheck:
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(Palette.paper.opacity(0.35)))
                    x += 6
                }
                ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)), with: .color(Palette.paper.opacity(0.35)))
            }
        }
    }
}

private struct TapeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // 两端锯齿：撕开的胶带
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 3, y: r.minY + r.height * 0.3))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 1, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 3, y: r.minY + r.height * 0.65))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.35))
        p.closeSubpath()
        return p
    }
}

/// 图钉：选中时变 `accent`。只在完整装饰下画。
struct Pin: View {
    var active = false
    @Environment(\.decor) private var decor

    var body: some View {
        if decor == .full {
            ZStack {
                Circle().fill(Palette.corkDeep.opacity(0.35)).frame(width: 12, height: 12).offset(x: 1.5, y: 2)
                Circle().fill(active ? Palette.accent : Palette.kraft).frame(width: 12, height: 12)
                Circle().fill(Palette.paper.opacity(0.6)).frame(width: 4, height: 4).offset(x: -2, y: -2)
            }
        }
    }
}

/// 便利贴：便利贴色 + 顶部胶带 + 右下角卷角。最弱装饰下只留颜色（浮窗里不歪、不加胶带）。
struct StickyNote<Content: View>: View {
    var color: Color = Palette.stickyPink
    var tape: TapeStyle? = .pinkDots
    var tilt: Double = 0
    @ViewBuilder var content: Content
    @Environment(\.decor) private var decor

    var body: some View {
        content
            .padding(.horizontal, 14).padding(.top, decor >= .low && tape != nil ? 16 : 10).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    Rectangle().fill(color)
                    if decor >= .low {
                        // 卷角：右下角一块三角阴影
                        CurlShape().fill(Palette.paperShadow).frame(width: 14, height: 14)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let tape, decor >= .low { Tape(style: tape).offset(y: -8) }
            }
            .compositingGroup()
            .shadow(color: decor >= .low ? Palette.paperShadow : .clear, radius: 2, x: 0, y: 1)
            .tilted(tilt)
    }
}

private struct CurlShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 拍立得：白卡、四周 8pt 留白、底部 32pt 写一行字，顶部一条胶带。最弱装饰下不画。
struct Polaroid<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content
    @Environment(\.decor) private var decor

    var body: some View {
        if decor >= .low {
            VStack(spacing: 0) {
                content
                Text(caption).font(.fee(.label)).foregroundStyle(Palette.ink).lineLimit(1)
                    .frame(height: 32)
            }
            .padding([.horizontal, .top], 8)
            .background(Palette.polaroid)
            .paperShadow()
            .overlay(alignment: .top) { Tape(style: .kraft).offset(y: -8) }
        }
    }
}

// MARK: 笔迹

/// 小节标题右边的手绘波浪线：振幅 2pt、波长 12pt、线宽 1.2pt。
struct WavyRule: View {
    var width: CGFloat? = nil

    var body: some View {
        WaveShape()
            .stroke(Palette.tertiary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: width, height: 6)
    }
}

private struct WaveShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY
        p.move(to: CGPoint(x: r.minX, y: mid))
        var x = r.minX
        while x <= r.maxX {
            p.addLine(to: CGPoint(x: x, y: mid + 2 * sin((x - r.minX) / 12 * 2 * .pi)))
            x += 1
        }
        return p
    }
}

/// 计数划记：每 5 个一组，前 4 竖、第 5 斜着划过去。
struct TallyMark: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<(count + 4) / 5, id: \.self) { g in
                TallyGroup(n: min(5, count - g * 5))
                    .stroke(Palette.link, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 16, height: 14)
            }
        }
    }
}

private struct TallyGroup: Shape {
    let n: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<min(n, 4) {
            let x = r.minX + 2 + CGFloat(i) * 4
            p.move(to: CGPoint(x: x, y: r.minY + 1))
            p.addLine(to: CGPoint(x: x + 0.5, y: r.maxY - 1))
        }
        if n >= 5 {
            p.move(to: CGPoint(x: r.minX, y: r.maxY - 3))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 3))
        }
        return p
    }
}

/// 术语吊牌：`kraft` 底，左边一个小孔。
struct KraftTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.paper).frame(width: 5, height: 5)
                .overlay(Circle().stroke(Palette.corkDeep.opacity(0.4), lineWidth: 0.5))
            Text(text).font(.fee(.label)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(TagShape().fill(Palette.kraft))
    }
}

private struct TagShape: Shape {
    func path(in r: CGRect) -> Path {
        // 左端切角的吊牌
        var p = Path()
        let c: CGFloat = min(6, r.height / 2)
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 2), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 2, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct HighlighterShape: Shape {
    func path(in r: CGRect) -> Path {
        // 两端略歪的一块，像荧光笔涂的
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 1, y: r.minY + 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: 样张（调试命令 paperRender）

/// 全部组件的样张：上排完整装饰，下排最弱装饰（浮窗看到的样子）。
struct PaperSampler: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            row.decor(.full)
            row.decor(.minimal)
        }
        .padding(24)
        .background(CorkBoard())
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 24) {
            NotebookPage(holes: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { Text("小节标题").font(.fee(.section)); WavyRule(width: 80) }
                        .frame(height: 48, alignment: .bottom)
                    Text("会议定在周四下午三点，Alice 负责 Q3 roadmap 的初稿。\nWe agreed to ship the beta on 12 December.\n第三行：结论里的数字要高亮。")
                        .ruledText(.body).foregroundStyle(Palette.body)
                    HStack(spacing: 6) { Text("荧光笔").ruledText(.body); Text("12 月 3 日").ruledText(.body).highlighted() }
                }
                .padding(.leading, PaperMetrics.marginX + 12).padding(.trailing, 16)
                .frame(width: 420, height: 264, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: 20) {
                StickyNote(color: Palette.stickyPink, tape: .pinkDots, tilt: -1) {
                    Label("给设计组发初稿", systemImage: "square").font(.fee(.body)).foregroundStyle(Palette.ink)
                }
                StickyNote(color: Palette.stickyYellow, tape: .greenCheck, tilt: 1) {
                    Text("我的批注").font(.fee(.body)).foregroundStyle(Palette.inkBlue)
                }
                StickyNote(color: Palette.stickyGreen, tape: .kraft) {
                    Text("已保存").font(.fee(.body)).foregroundStyle(Palette.ink)
                }
            }
            .frame(width: 200)
            VStack(alignment: .leading, spacing: 16) {
                Polaroid(caption: "正在听") { Palette.paperShade.frame(width: 120, height: 120) }
                HStack(spacing: 12) { Pin(); Pin(active: true); TallyMark(count: 7) }
                KraftTag(text: "Q3 roadmap")
            }
        }
    }
}
