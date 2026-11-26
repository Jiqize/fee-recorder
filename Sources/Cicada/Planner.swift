import SwiftUI

// 第二轮主窗口：一本焦糖皮面手帐摊开（DESIGN.md › 主窗口（第二轮 · 手帐），样稿 round2-planner.html）。
// 这里只放外壳的部件：皮面、两页共用的一张横线纸、上沿索引贴、右边分隔页、笔插里的笔、印章。

enum PlannerMetrics {
    /// 摊开的两页离窗边的距离（样稿 1280×800 里的位置）。
    static let top: CGFloat = 48
    static let leading: CGFloat = 44
    static let trailing: CGFloat = 92
    static let bottom: CGFloat = 30
    /// 右页上沿索引贴离右页左边的距离。
    static let tabsInset: CGFloat = 88

    static func leftWidth(window: CGFloat) -> CGFloat { window >= 1100 ? 340 : 280 }

    /// 两页的高度取 24 的整数倍：页脚那一行也落在横线上，多出来的给下面的皮面。
    static func spreadHeight(window: CGFloat) -> CGFloat {
        max(PaperMetrics.pitch * 10, ((window - top - bottom) / PaperMetrics.pitch).rounded(.down) * PaperMetrics.pitch)
    }
}

// MARK: 皮面

/// 焦糖色皮面：斜向渐变 + 两层细点压纹 + 距窗边 12pt 一圈虚线缝线。
struct LeatherCover: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.leatherLight, Palette.leather, Palette.leatherDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                var rnd = Seeded(11)
                let count = Int(size.width * size.height / 30)
                for _ in 0..<min(count, 40_000) {
                    let p = CGRect(x: rnd.next() * size.width, y: rnd.next() * size.height, width: 1.4, height: 1.4)
                    let light = rnd.next() > 0.5
                    ctx.fill(Path(ellipseIn: p), with: .color(light ? Palette.paper.opacity(0.07) : Palette.corkDeep.opacity(0.12)))
                }
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.stitch, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(12)
        }
        .allowsHitTesting(false)
    }
}

// MARK: 两页一张纸

/// 摊开的两页：一个画布画纸、纸纹、横线和右页的红页边线；中缝不画任何东西。底边露出几层纸的厚度。
struct SpreadPaper: View {
    let leftWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
            ctx.fill(shape, with: .color(Palette.paper))
            ctx.clip(to: shape)
            var rnd = Seeded(7)
            for _ in 0..<min(Int(size.width * size.height / 90), 20_000) {
                let p = CGRect(x: rnd.next() * size.width, y: rnd.next() * size.height, width: 1.2, height: 1.2)
                ctx.fill(Path(ellipseIn: p), with: .color(Palette.kraft.opacity(0.04)))
            }
            var y = PaperMetrics.pitch
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(Palette.rule))
                y += PaperMetrics.pitch
            }
            ctx.fill(Path(CGRect(x: leftWidth + PaperMetrics.marginX - 0.5, y: 0, width: 1, height: size.height)),
                     with: .color(Palette.margin))
        }
        .background(alignment: .bottom) {
            // 几层纸的厚度：浅深相间的细条
            Canvas { ctx, size in
                var y: CGFloat = 0, i = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(i % 2 == 0 ? Palette.paperEdgeLight : Palette.paperEdge))
                    y += 1; i += 1
                }
            }
            .frame(height: 6)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4))
            .padding(.horizontal, 2)
            .offset(y: 6)
        }
        .compositingGroup()
        .shadow(color: Palette.leatherShadow, radius: 10, x: 0, y: 6)
        .allowsHitTesting(false)
    }
}

/// 右页滚动停下时对齐 24pt，字回到静态横线上。
struct RuleSnapScroll: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let pitch = PaperMetrics.pitch
        let maxY = max(0, context.contentSize.height - context.containerSize.height)
        let snapped = (target.rect.origin.y / pitch).rounded() * pitch
        target.rect.origin.y = min(max(0, snapped), maxY)
    }
}

// MARK: 索引贴、分隔页

/// 从右页上沿伸出去的索引贴：选中的和纸同色连成一体，没选中的浅蓝、矮一截。
struct PageTabs: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var count: Int? = nil
        var disabled = false
        var help: String? = nil
    }

    let items: [Item]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(items) { item in
                let on = item.id == selected
                Button { pick(item.id) } label: {
                    HStack(spacing: 6) {
                        Text(item.title).font(.fee(.body, strong: on)).foregroundStyle(Palette.ink)
                        if let count = item.count {
                            Text("\(count)").font(.fee(.meta)).foregroundStyle(Palette.tertiary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: on ? 30 : 25)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                        .fill(on ? Palette.paper : Palette.tabBack))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.disabled)
                .opacity(item.disabled ? 0.6 : 1)
                .help(item.help ?? "")
            }
        }
        .fixedSize()
    }
}

/// 竖排的字：中日韩文逐字往下写；拉丁字母、数字、⌘ 这类连成一段整体转 90°（「开始听 ⌘R」= 三个字竖写 + 横躺的 ⌘R）。
/// 整段都是拉丁字母时就是一整条转 90° 的字。
struct VerticalLabel: View {
    let text: String
    var length: CGFloat = 70
    /// 整条英文的宽度：比 `length` 长时整体缩小，不压到下一张分隔页（设置七张分隔页时的 Diagnostics）。
    @State private var latinWidth: CGFloat = 0

    private static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
    }

    /// 按「中日韩单字 / 其他连成的一段」切开，空格丢掉。
    static func runs(_ text: String) -> [(text: String, upright: Bool)] {
        var out: [(text: String, upright: Bool)] = []
        var latin = ""
        for c in text {
            if isCJK(c) {
                if !latin.isEmpty { out.append((latin, false)); latin = "" }
                out.append((String(c), true))
            } else if c == " " {
                if !latin.isEmpty { out.append((latin, false)); latin = "" }
            } else {
                latin.append(c)
            }
        }
        if !latin.isEmpty { out.append((latin, false)) }
        return out
    }

    var body: some View {
        let parts = Self.runs(text)
        if parts.contains(where: \.upright) {
            VStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, run in
                    // 两个字符以内（⌘R）直接立着写，放得下；更长的英文词才横躺
                    if run.upright || run.text.count <= 2 { Text(run.text).fixedSize() } else { Sideways(text: run.text) }
                }
            }
        } else {
            Text(text).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { latinWidth = $0 }
                .scaleEffect(latinWidth > length ? length / latinWidth : 1)
                .rotationEffect(.degrees(90))
                .frame(width: 18, height: length)
        }
    }

    /// 一段横躺的字：转 90°，占的高度按字宽算。
    private struct Sideways: View {
        let text: String
        @State private var width: CGFloat = 0
        var body: some View {
            Text(text).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .rotationEffect(.degrees(90))
                .frame(width: 18, height: max(width, 10))
                .padding(.top, 4)
        }
    }
}

/// 从本子右边缘伸出来的彩色分隔页：当前那张更宽、字加粗。画在纸下面，左边一截压在纸里。
struct DividerTabs: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let color: Color
        var badge: String? = nil
        /// 小字的颜色：数字是红铅笔，做完的 ✓ 是绿色。
        var badgeColor: Color = Palette.link
    }

    let items: [Item]
    let selected: String
    /// 每张的高度和间距：主窗口四张 86 / 8；设置六张用矮一点的。
    var tabHeight: CGFloat = 86
    var gap: CGFloat = 8
    let pick: (String) -> Void
    /// 压在纸下面的那一截。
    static let tucked: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(items) { item in
                let on = item.id == selected
                Button { pick(item.id) } label: {
                    VStack(spacing: 6) {
                        VerticalLabel(text: item.title, length: min(item.badge == nil ? 70 : 56, tabHeight - 10)).font(.fee(.body, strong: on)).foregroundStyle(Palette.ink)
                        if let badge = item.badge {
                            Text(badge).font(.fee(.caption)).foregroundStyle(item.badgeColor)
                        }
                    }
                    .padding(.leading, Self.tucked)
                    .frame(width: (on ? 54 : 46) + Self.tucked, height: tabHeight)
                    .background(UnevenRoundedRectangle(bottomTrailingRadius: 9, topTrailingRadius: 9).fill(item.color))
                    .compositingGroup()
                    .shadow(color: Palette.ink.opacity(0.25), radius: 1.5, x: 2, y: 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
    }
}

// MARK: 笔插里的笔

/// 皮质笔插里插着一支红帽笔，笔身竖写「开始听 ⌘R」；正在听时笔抽出一截，笔帽顶上一个呼吸的点。
struct PenInLoop: View {
    let listening: Bool
    let label: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 40, height: 300)

    var body: some View {
        ZStack(alignment: .top) {
            // 笔插：一截皮带
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Palette.leatherDeep, Palette.leather, Palette.leatherDeep],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.stitch, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(4))
                .frame(width: 40, height: 140)
                .shadow(color: Palette.ink.opacity(0.35), radius: 3, x: -1, y: 2)
                .offset(y: 86)
            Button(action: action) {
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(topLeadingRadius: 13, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 13)
                        .fill(LinearGradient(colors: [Palette.error, Palette.accent, Palette.error], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 26, height: 92)
                        .overlay(alignment: .topTrailing) {
                            // 笔夹
                            RoundedRectangle(cornerRadius: 3).fill(Palette.placeholder)
                                .frame(width: 6, height: 60).offset(x: 5, y: 10)
                        }
                        .overlay(alignment: .top) { if listening { BreathingDot(size: 7).padding(.top, 9) } }
                        // 正在听：笔帽亮一圈红光
                        .shadow(color: Palette.accent.opacity(listening ? 0.6 : 0), radius: 9)
                    Rectangle()
                        .fill(LinearGradient(colors: [Palette.ink, Palette.body, Palette.ink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 26, height: 208)
                        .overlay(alignment: .top) {
                            VerticalLabel(text: label, length: 150).font(.fee(.label)).foregroundStyle(Palette.stickyYellow)
                                .padding(.top, 14)
                        }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: listening ? -56 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: listening)
            .accessibilityLabel(label)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }
}

// MARK: 印章、涂鸦

/// 墨水圆印章：外圈实线、内圈虚线，略歪；「分享」「导出」用。
struct InkStamp: View {
    let text: String
    let color: Color
    var tilt: Double = -9

    var body: some View {
        Text(text).font(.fee(.body, strong: true)).foregroundStyle(color)
            .frame(width: 62, height: 62)
            .overlay(Circle().stroke(color, lineWidth: 2.2))
            .overlay(Circle().stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(5))
            .rotationEffect(.degrees(tilt))
            .opacity(0.86)
            .contentShape(Circle())
    }
}

/// 页边的菲比涂鸦：当前状态图，歪着贴在右页右上角。
struct FeebeeDoodle: View {
    let mood: FeebeeMood
    var size: CGFloat = 104

    var body: some View {
        FeebeeView(mood: mood, size: size).rotationEffect(.degrees(6)).allowsHitTesting(false)
    }
}

// MARK: 左页「这一周」

/// 大号日期：日（大字）+ 月和星期（两行小字）+ 右边红圈「待办 N」印章。占三格（72pt）。
struct PlannerBigDate: View {
    let big: String
    let lines: [String]
    var todo: (count: Int, open: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(big).font(.feeHero(big.count > 2 ? 40 : 62)).foregroundStyle(Palette.ink)
                .lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) { Text($0).frame(height: PaperMetrics.pitch) }
            }
            .font(.fee(.body)).foregroundStyle(Palette.secondary)
            Spacer(minLength: 4)
            if let todo, todo.count > 0 {
                Button(action: todo.open) {
                    VStack(spacing: 0) {
                        Text("待办")
                        Text("\(todo.count)")
                    }
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.link)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .overlay(Ellipse().stroke(Palette.link, lineWidth: 1.8))
                    .rotationEffect(.degrees(-8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("打开待办板"))
            }
        }
        .frame(height: PaperMetrics.pitch * 3)
    }
}

/// 一周七个圆：所看那天实心墨色，今天描一圈，有会议的日子下面一个小点。占两格。
struct WeekStrip: View {
    let days: [Date]
    let focus: Date
    let meetingDays: Set<Date>
    let pick: (Date) -> Void
    var calendar = PlannerCalendar.calendar

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let on = calendar.isDate(d, inSameDayAs: focus)
                let today = calendar.isDateInToday(d)
                Button { pick(d) } label: {
                    // 上面一个小小的星期几，下面日子的圆（第三轮样稿）
                    VStack(spacing: 0) {
                        Text(dateText(d, "EEEEE")).font(.fee(.caption)).foregroundStyle(Palette.placeholder)
                            .frame(height: 14)
                        Text("\(calendar.component(.day, from: d))")
                            .font(.fee(.label, strong: on || today))
                            .foregroundStyle(on ? Palette.paper : Palette.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(on ? Palette.ink : .clear))
                            .overlay(Circle().stroke(today ? (on ? Palette.accent : Palette.ink) : .clear, lineWidth: 1.3))
                    }
                    .overlay(alignment: .bottom) {
                        if meetingDays.contains(calendar.startOfDay(for: d)) {
                            Circle().fill(Palette.accent).frame(width: 5, height: 5).offset(y: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(dateText(d, "MMMdEEEE"))
            }
        }
        .frame(height: PaperMetrics.pitch * 2)
    }
}

/// 一个月的月历：上面一行星期，下面每周一行（各占一格），有会议的日子下面一个小点。
struct MonthGrid: View {
    let rows: [[Date?]]
    let focus: Date
    let meetingDays: Set<Date>
    let pick: (Date) -> Void
    var calendar = PlannerCalendar.calendar

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(PlannerCalendar.week(containing: focus, calendar: calendar).enumerated()), id: \.offset) { _, d in
                    Text(dateText(d, "EEEEE")).font(.fee(.caption)).foregroundStyle(Palette.tertiary).frame(maxWidth: .infinity)
                }
            }
            .frame(height: PaperMetrics.pitch)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, d in
                        if let d {
                            let on = calendar.isDate(d, inSameDayAs: focus)
                            Button { pick(d) } label: {
                                Text("\(calendar.component(.day, from: d))")
                                    .font(.fee(.caption, strong: on))
                                    .foregroundStyle(on ? Palette.paper : Palette.secondary)
                                    .frame(width: 21, height: 21)
                                    .background(Circle().fill(on ? Palette.ink : .clear))
                                    .overlay(alignment: .bottomTrailing) {
                                        if meetingDays.contains(calendar.startOfDay(for: d)) {
                                            Circle().fill(Palette.accent).frame(width: 4, height: 4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity).frame(height: PaperMetrics.pitch)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: PaperMetrics.pitch)
                        }
                    }
                }
            }
        }
    }
}

/// 时间线上的一场会议：圆点挂在竖线上；三格：时间 · 时长 / 标题 / 说话人头像。选中的标题加粗、划荧光笔；
/// 正在听的圆点外一圈 `accent` 光晕。
struct TimelineEntry<Title: View>: View {
    let meta: String
    let selected: Bool
    let live: Bool
    let avatars: [String]
    @ViewBuilder var title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(meta).font(.fee(.label)).foregroundStyle(Palette.tertiary).lineLimit(1)
                .frame(height: PaperMetrics.pitch)
            title
                .font(.fee(.section, strong: selected)).foregroundStyle(Palette.ink).lineLimit(1)
                .frame(height: PaperMetrics.pitch)
                .background(alignment: .leading) {
                    if selected {
                        // 荧光笔划在字的下半截
                        Rectangle().fill(Palette.mark.opacity(0.65)).frame(height: 9).offset(y: 5).padding(.horizontal, -2)
                    }
                }
            if !avatars.isEmpty {
                HStack(spacing: -5) {
                    ForEach(Array(avatars.enumerated()), id: \.offset) { _, name in
                        if let picture = Illustration.image(name) {
                            Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .frame(height: PaperMetrics.pitch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
        .overlay(alignment: .topLeading) {
            Circle().fill(live || selected ? (live ? Palette.paper : Palette.accent) : Palette.paper)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(live || selected ? Palette.accent : Palette.secondary, lineWidth: 2))
                .background { if live { Circle().fill(Palette.accent.opacity(0.2)).padding(-4) } }
                .padding(.leading, 1).padding(.top, 6.5)
        }
        .padding(.bottom, PaperMetrics.pitch)
        .contentShape(Rectangle())
    }
}

extension View {
    /// 时间线的竖线：x = 6.5，从第一个圆点到最后一个。
    func timelineRail() -> some View {
        background(alignment: .leading) {
            Rectangle().fill(Palette.placeholder).frame(width: 1.5)
                .padding(.leading, 6).padding(.top, 12).padding(.bottom, PaperMetrics.pitch + 12)
        }
    }
}

/// 待办页左页的七天格：每天一格（三格高），当天描墨色边，到期的待办画成底下一根彩色小条。
struct DueWeekStrip: View {
    let days: [Date]
    let counts: [Int]
    let overdue: Int
    var calendar = PlannerCalendar.calendar

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = calendar.isDateInToday(d)
                let n = i < counts.count ? counts[i] : 0
                VStack(alignment: .leading, spacing: 0) {
                    Text(dateText(d, "EEE")).font(.fee(.caption)).foregroundStyle(Palette.tertiary)
                    Text("\(calendar.component(.day, from: d))").font(.fee(.section)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    if n > 0 {
                        // 条的长短 = 到期几条（最多三条画满）
                        GeometryReader { g in
                            Capsule().fill(today ? Palette.accent : Palette.accent.opacity(0.75))
                                .frame(width: max(8, g.size.width * min(1, Double(n) / 3)))
                        }
                        .frame(height: 6)
                    }
                }
                .padding(.horizontal, 5).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PaperMetrics.pitch * 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.polaroid.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(today ? Palette.ink : Palette.hairline, lineWidth: 1))
                .help(n > 0 ? L("\(n) 条到期") : dateText(d, "MMMdEEEE"))
            }
        }
    }
}

// MARK: 右页的页边贴纸栏

enum StripMetrics {
    static let width: CGFloat = 176
    /// 右页窄于这个宽度时贴纸栏收起：待办回正文，印章回右下角。
    static let minPage: CGFloat = 680
}

/// 贴在页边的一张牛皮纸签（「原话 ›」「本场 4 人 · 10 句」）。
struct StripTag: View {
    let text: String

    var body: some View {
        Text(text).font(.fee(.bodySecondary)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 12).frame(height: PaperMetrics.pitch)
            .background(Rectangle().fill(Palette.kraft))
            .paperShadow()
            .rotationEffect(.degrees(-2))
    }
}

/// 页边栏里的录音：手画的播放钮、倍速、时间和一支铅笔进度条（点铅笔跳到那里）。
struct StripPlayer: View {
    @ObservedObject var player: RecordingPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if player.missing {
                Text(player.own ? L("找不到录音，没法播放") : L("找不到原文件，没法播放"))
                    .font(.fee(.label)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.icon(13))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Palette.ink, lineWidth: 2))
                            .rotationEffect(.degrees(-4))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain).help(player.playing ? L("暂停") : L("播放"))
                    Spacer()
                    Button { player.nextRate() } label: {
                        NotebookWord { Text(player.rate == 1 ? "1×" : player.rate == 1.5 ? "1.5×" : "2×") }
                    }
                    .buttonStyle(.plain).help(L("播放速度"))
                }
                HStack {
                    Text("录音").foregroundStyle(Palette.secondary)
                    Spacer()
                    Text("\(TranscriptExport.clock(player.time)) / \(TranscriptExport.clock(player.length))").foregroundStyle(Palette.ink)
                }
                .font(.fee(.meta))
                GeometryReader { g in
                    PencilBar(fraction: player.length > 0 ? player.time / player.length : 0)
                        .contentShape(Rectangle())
                        .onTapGesture { p in
                            guard player.length > 0, g.size.width > 0 else { return }
                            player.seek(min(1, max(0, p.x / g.size.width)) * player.length)
                        }
                }
                .frame(height: 16)
                .help(L("点铅笔跳到那里"))
            }
        }
    }
}

// MARK: 和纸胶带

private struct Washi: ViewModifier {
    let color: Color
    @Environment(\.decor) private var decor
    func body(content: Content) -> some View {
        if decor == .full {
            content.padding(.horizontal, 8).frame(height: 20)
                .background(Rectangle().fill(color.opacity(0.16)))
                .rotationEffect(.degrees(-1.5))
        } else {
            content
        }
    }
}

extension View {
    /// 说话人名字贴在一截彩色和纸胶带上（只在完整装饰下；实时纪要窗不变）。
    func washi(_ color: Color) -> some View { modifier(Washi(color: color)) }
}

// MARK: 正在听：铅笔虚线占位、此刻便签

/// 还没写出来的纪要：一行铅笔虚线，慢慢从左往右写长（循环）；减少动态效果时就是一条静止的虚线。
struct PencilScribble: View {
    var fraction: CGFloat = 0.8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { ctx in
                // 2.4 秒写满一次：先写到 fraction，停一下再从头写
                let t = reduceMotion ? 1 : min(1, (ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4)) / 1.8)
                Canvas { c, size in
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width * fraction * t, y: size.height / 2))
                    c.stroke(p, with: .color(Palette.placeholder), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [9, 4]))
                }
            }
            .frame(width: g.size.width)
        }
        .frame(height: PaperMetrics.pitch)
        .accessibilityHidden(true)
    }
}

/// 主窗口里纪要还没出来时：角色栏「摘要」+ 一句话（在听 / 在写）+ 几行铅笔虚线，下面「议题」再两行。
struct NotebookPendingNotes: View {
    let writing: Bool
    let heard: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GutterRow(gutter: {
                Text("摘要").font(.fee(.label, strong: true)).foregroundStyle(Palette.link)
                    .frame(height: PaperMetrics.pitch).padding(.trailing, 12)
            }) {
                Group {
                    if writing {
                        Text("菲比在写纪要，马上就好…")
                    } else if heard > 0 {
                        Text(L("菲比在听，说到第 \(heard) 句了，纪要马上写出来…"))
                    } else {
                        Text("有人开口后，约半分钟出第一版")
                    }
                }
                .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).frame(height: PaperMetrics.pitch)
            }
            GutterRow { PencilScribble(fraction: 0.9) }
            GutterRow { PencilScribble(fraction: 0.62) }
            Color.clear.frame(height: PaperMetrics.pitch)
            GutterRow { NotebookHeading(title: L("议题")) }
            GutterRow { PencilScribble(fraction: 0.45) }
            GutterRow { PencilScribble(fraction: 0.7) }
        }
    }
}

// MARK: 动效

/// 翻页：右页沿中缝（左边）转过来一点再落平，同时淡入。
struct PageTurn: ViewModifier {
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var pageTurn: AnyTransition {
        .asymmetric(insertion: .modifier(active: PageTurn(angle: -24, opacity: 0), identity: PageTurn(angle: 0, opacity: 1)),
                    removal: .opacity)
    }
}

/// 贴上：出现时从略大、阴影深「按」到纸上，0.2 秒；减少动态效果时直接出现。
private struct PressOn: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(on || reduceMotion ? 1 : 1.06)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { on = true } }
    }
}

extension View {
    func pressedOn() -> some View { modifier(PressOn()) }
}
