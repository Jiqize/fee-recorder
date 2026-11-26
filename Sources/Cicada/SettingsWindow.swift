import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overlay, language, words, speak, records, ai, diagnostics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overlay: L("显示")
        case .language: L("语言")
        case .words: L("词表")
        case .speak: L("同声传译")
        case .records: L("通用")
        case .ai: L("AI 服务")
        case .diagnostics: L("诊断")
        }
    }
    /// 分隔页上竖写的短名（样稿 round3 › 设置）：长的两个缩短，英文竖着也放得进一张分隔页。
    var tabTitle: String {
        switch self {
        // 「同传」的英文是 Interpreted（形容词），分隔页单用一个新词
        case .speak: L("传译")
        case .ai: "AI"
        default: title
        }
    }
    var icon: String {
        switch self {
        case .overlay: "captions.bubble"
        case .language: "globe"
        case .words: "character.book.closed"
        case .speak: "mic"
        case .records: "gearshape"
        case .ai: "key"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

// MARK: - Building blocks

/// A white card of rows separated by hairlines, like System Settings.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.decor) private var decor
    var body: some View {
        // 纸面上（设置窗口）不装卡片，直接写在纸上；别处仍是一张纸色卡片
        if decor >= .medium {
            VStack(spacing: 0) { content }
        } else {
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    /// A small state mark before the title, e.g. 共享屏幕时让对方看到's.
    var mark: AnyView? = nil
    @ViewBuilder var trailing: Trailing
    @Environment(\.decor) private var decor
    var body: some View {
        let paper = decor >= .medium
        if paper { paperRow } else { cardRow }
    }

    /// 纸面上（样稿 round3 › 设置）：第一格是标题和右边的控件，说明另起一格写满整行，字都落在横线上。
    private var paperRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let mark { mark }
                // 英文、日文、韩文长一些会折行：每行占一格，折了也还落在横线上
                Text(title).ruledText(.body).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                // 按钮、键帽比一格高一点：只占一格排版，多出的往下画到格外，后面的字不往下错
                //（快捷键被拒时下面多一行红字，也是往下长）
                trailing.frame(height: PaperMetrics.pitch, alignment: .top)
            }
            .frame(minHeight: PaperMetrics.pitch)
            // 报给设置页：页边按这一格写红铅笔编号
            .anchorPreference(key: SettingsGutterKey.self, value: .bounds) { [$0] }
            if let detail {
                Text(detail).ruledText(.bodySecondary).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: PaperMetrics.pitch)
            }
        }
    }

    /// 卡片上（不是纸面时）：原来的排法；`paper` 留着，和上游的写法对得上
    private var cardRow: some View {
        let paper = false
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let mark { mark }
                VStack(alignment: .leading, spacing: paper ? 0 : 2) {
                    Text(title).font(.fee(.body)).foregroundStyle(Palette.ink)
                        .frame(minHeight: paper ? PaperMetrics.pitch : nil)
                    if let detail {
                        Text(detail).font(.fee(paper ? .bodySecondary : .label)).foregroundStyle(paper ? Palette.secondary : Palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: paper ? PaperMetrics.pitch : nil)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            // 纸面上每项占整数格、不画分隔线
            .padding(.horizontal, paper ? 0 : 16).padding(.vertical, paper ? 0 : 6)
            .frame(minHeight: paper ? PaperMetrics.pitch * 2 : 46)
            if divider && !paper { Divider().padding(.leading, 16) }
        }
    }
}

/// 纸面上每个设置项第一格的位置，按排版顺序收集（样稿 round3 › 设置：页边红铅笔编号）。
/// 设置页在页边统一写号，所以别的文件里的 `SettingsRow` 也自动编上，按条件出现的项也不会错号。
struct SettingsGutterKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// 页边的编号：红线（64pt）左边，右对齐，和这一项的第一格齐平。
struct SettingsGutterNumbers: View {
    let anchors: [Anchor<CGRect>]
    var body: some View {
        GeometryReader { g in
            let rows = anchors.map { g[$0] }.sorted { $0.minY < $1.minY }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                Text(verbatim: "\(i + 1)").font(.fee(.label, strong: true)).foregroundStyle(Palette.link)
                    .frame(width: 28, height: PaperMetrics.pitch, alignment: .trailing)
                    .position(x: PaperMetrics.marginX - 8 - 14, y: r.minY + PaperMetrics.pitch / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A few mutually exclusive choices side by side: on paper a row of words, the chosen one
/// circled in red pencil (settings, the menu bar panel and the windows alike).
struct Segments: View {
    let options: [(id: String, title: String)]
    let value: String
    /// 平分给定的宽度（菜单栏面板里两组选项右边对齐）。
    var fill = false
    /// 原来灰色分段控件的底色；纸上不垫底色，参数留着和上游的调用对得上。
    var track = Palette.fill
    let onPick: (String) -> Void
    @Environment(\.decor) private var decor

    var body: some View {
        // 菜单栏面板（低装饰）地方窄：字小一号、词挨得近一点
        let compact = decor < .medium
        HStack(spacing: compact ? 10 : 20) {
            ForEach(options, id: \.id) { o in
                let on = o.id == value
                Button { onPick(o.id) } label: {
                    Text(o.title).font(.fee(compact ? .bodySecondary : .body, strong: on))
                        .foregroundStyle(on ? Palette.ink : Palette.tertiary).lineLimit(1).fixedSize()
                        .padding(.horizontal, 4)
                        .overlay {
                            if on {
                                PencilCircle().stroke(Palette.link, style: StrokeStyle(lineWidth: compact ? 1.5 : 1.8, lineCap: .round))
                                    .padding(.horizontal, compact ? -5 : -8).padding(.vertical, -3)
                            }
                        }
                        // 点的地方至少一格高
                        .frame(maxWidth: fill ? .infinity : nil).frame(height: PaperMetrics.pitch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .fixedSize(horizontal: !fill, vertical: false)
    }
}

/// 字幕条: shown while someone talks, or always. Settings and the menu bar panel.
@MainActor func overlayAutoSegments(model: AppModel, fill: Bool = false, track: Color = Palette.fill) -> some View {
    Segments(options: [("auto", L("有人说话时")), ("always", L("始终显示"))],
                    value: model.settings.overlayAuto ? "auto" : "always", fill: fill, track: track) { model.setOverlayAuto($0 == "auto") }
}

/// 字幕条: how long it waits after the last words before tucking away.
@MainActor func hideAfterSegments(settings: AppSettings, fill: Bool = false, track: Color = Palette.fill) -> some View {
    Segments(options: [2.0, 4, 8].map { (String(Int($0)), L("\(Int($0)) 秒")) },
             value: String(Int(settings.overlayHideAfter)), fill: fill, track: track) { settings.overlayHideAfter = Double($0) ?? 4 }
}

/// The 字幕 choices.
let subtitleOptions: [(id: String, title: String)] = [("both", L("原文 + 译文")), ("translation", L("只看译文")), ("original", L("只看原文"))]

/// A value that opens a menu: on paper a dashed word and a small ⌄ (样稿 round4 ③), no fill,
/// so the ruled lines show through.
struct PillMenu: View {
    let value: String
    let options: [(id: String, title: String)]
    let onPick: (String) -> Void
    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in Button(o.title) { onPick(o.id) } }
        } label: {
            HStack(spacing: 4) {
                Text(value).font(.fee(.body)).foregroundStyle(Palette.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.icon(9, weight: .semibold)).foregroundStyle(Palette.secondary)
            }
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                PencilLine().stroke(Palette.placeholder, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
            }
            .frame(height: PaperMetrics.pitch)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

struct SoftButton: View {
    let title: String
    var dark = false
    /// White, for a button sitting on a grey card.
    var onGrey = false
    /// 字前面的小图标（试一句的 ▶）。
    var icon: String? = nil
    let action: () -> Void
    init(_ title: String, dark: Bool = false, onGrey: Bool = false, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.dark = dark
        self.onGrey = onGrey
        self.icon = icon
        self.action = action
    }
    var body: some View {
        // 纸面小方块：浅的是 paperShade + 细边，深的是墨色底纸色字；下面一道硬阴影
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.icon(9)) }
                Text(title)
            }
            .font(.fee(.bodySecondary, strong: true))
                .foregroundStyle(dark ? Palette.paper : Palette.ink)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Rectangle().fill(dark ? Palette.ink : onGrey ? Palette.paper : Palette.paperShade))
                .overlay(Rectangle().stroke(dark ? Palette.ink : Palette.hairline, lineWidth: 1))
                // 纸方块：右下一道 1.5pt 硬阴影（第四轮样稿）
                .background(Rectangle().fill(dark ? Palette.tertiary : Palette.placeholder).offset(x: 1.5, y: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 左页底下的版本行：「菲比 · 版本 x · 检查更新」，检查更新是虚线字（同「通用」里的检查更新）。
/// 一行放不下（英文）时，虚线字另起一格。
private struct VersionLine: View {
    let text: String
    @ObservedObject var updates: Updates
    /// 有新版本时点它：翻到「通用」，那里能安装。
    let showUpdate: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { version; Text(verbatim: "·").font(.fee(.label)).foregroundStyle(Palette.tertiary); word }
            VStack(alignment: .leading, spacing: 0) { version; word }
        }
    }

    private var version: some View {
        Text(verbatim: text).font(.fee(.label)).foregroundStyle(Palette.tertiary).lineLimit(1).fixedSize()
            .frame(height: PaperMetrics.pitch)
    }

    private var title: String {
        if let u = updates.update { return L("有新版本 \(u.version)") }
        switch updates.check {
        case .checking: return L("正在检查…")
        case .upToDate: return L("已是最新版本")
        default: return L("检查更新")
        }
    }

    private var word: some View {
        Button { updates.update != nil ? showUpdate() : updates.checkNow() } label: {
            Text(title).font(.fee(.label)).foregroundStyle(updates.update != nil ? Palette.link : Palette.secondary)
                .lineLimit(1).fixedSize()
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    PencilLine().stroke(Palette.placeholder, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
                }
                .frame(height: PaperMetrics.pitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updates.check == .checking)
    }
}

// MARK: - Shortcut field

/// Shows a shortcut as key caps; click it, then press the new keys (esc cancels).
/// The talk key also accepts the right ⌥ on its own.
struct ShortcutField: View {
    @ObservedObject var model: AppModel
    let role: AppModel.ShortcutRole
    @State private var recording = false
    @State private var error: String?
    @State private var monitor: Any?
    @State private var rightDown = false

    private var current: Shortcut { role == .talk ? model.settings.talkKey : model.settings.toggleKey }
    private var standard: Shortcut { role == .talk ? .defaultTalk : .defaultToggle }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if current != standard && !recording {
                    Button { error = model.setShortcut(standard, for: role) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.icon(11, weight: .semibold))
                            .foregroundStyle(Palette.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("恢复默认（\(standard.display)）")
                }
                Button { recording ? stop() : start() } label: {
                    HStack(spacing: 4) {
                        if recording {
                            Text(role == .talk ? L("按下组合键，或单按右 ⌥") : L("按下新的组合键"))
                                .font(.fee(.bodySecondary, strong: true)).foregroundStyle(Palette.accentInk)
                        } else {
                            ForEach(Array(current.keys.enumerated()), id: \.offset) { KeyCap($0.element) }
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    // 等按键时贴一张粉便签、红框（方角）；平时只有键帽
                    .background(Rectangle().fill(recording ? Palette.stickyPink : .clear))
                    .overlay(Rectangle().stroke(recording ? Palette.accentInk : .clear, lineWidth: 1.2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recording ? L("按 esc 取消") : L("点击更换按键"))
            }
            if let error {
                Text(error).font(.fee(.label)).foregroundStyle(Palette.accentInk)
            }
        }
        .onDisappear { stop() }
        // Another app grabbed the keys (its launcher came up): stop waiting for them.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        error = nil
        recording = true
        rightDown = false
        model.suspendShortcuts(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        model.suspendShortcuts(false)
    }

    private func handle(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch e.type {
        case .keyDown:
            if e.keyCode == UInt16(kVK_Escape) && flags.isEmpty { stop(); return }
            commit(Shortcut(keyCode: e.keyCode, flags: flags))
        case .flagsChanged:
            if role == .talk && e.keyCode == UInt16(kVK_RightOption) {
                // Right ⌥ pressed and released with nothing else: that's the choice.
                if e.modifierFlags.rawValue & 0x40 != 0 { rightDown = true } else if rightDown { commit(.rightOption) }
            } else {
                rightDown = false
            }
        default:
            break
        }
    }

    private func commit(_ s: Shortcut) {
        error = model.setShortcut(s, for: role)
        stop()
    }
}

/// "输入监控" is missing for the right ⌥ key: one line and a button.
struct TalkKeyPermissionRow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        SettingsRow(title: L("还差一步：允许“输入监控”"),
                    detail: L("“按住右 ⌥ 说话”需要此权限。请在系统设置中勾选 \(appDisplayName)，返回此处即可生效")) {
            SoftButton(L("去允许"), dark: true) { model.allowTalkKey() }
        }
    }
}

/// A check, an exclamation mark, or (speaking off) a grey dash: on paper a hand-drawn box
/// (green tick / red box / dashed box).
struct HealthMark: View {
    let ok: Bool
    let on: Bool
    /// On a tinted problem row the pale circle would vanish (paper: no circle any more).
    var onTint = false
    var body: some View {
        PaperCheck(mark: !ok ? .failed : on ? .done : .skipped)
            .frame(width: 20, height: 20)
    }
}

// MARK: - Virtual microphone checklist

/// The one place the virtual mic is set up: onboarding step 4 and the settings window.
/// Not ready → a three-step checklist with one button that does the next step.
/// Ready → one line with a status dot and the sound test.
struct MicSetupCard: View {
    @ObservedObject var installer: VirtualMicInstaller
    /// Re-read the device list when the app's copy changes.
    var deviceName: String?

    private var onDisk: Bool { installer.isOnDisk || deviceName != nil }
    private var loaded: Bool { deviceName != nil }

    var body: some View {
        if loaded && installer.passed && installer.state != .testing {
            ready
        } else {
            checklist
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(Palette.ok).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("虚拟麦克风已就绪").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                    Text("\(deviceName ?? "BlackHole 2ch") · 试音通过，对方听得到").font(.fee(.label)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                SoftButton(L("再试一次")) { installer.runTest() }
            }
            if let t = installer.test { TestResultView(result: t) }
        }
        .padding(.vertical, 12)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("虚拟麦克风").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                Spacer()
                StampLabel(text: statusTag, color: installer.busy ? Palette.accentInk : Palette.secondary)
            }
            step(1, L("安装"), L("输一次电脑密码"), done: onDisk,
                 active: installer.state == .downloading || installer.state == .installing,
                 activeText: installer.state == .downloading ? L("正在下载…") : L("正在安装…"))
            step(2, L("让系统认出它"), L("声音会短暂中断约 1 秒"), done: loaded,
                 active: installer.state == .reloading, activeText: L("正在让系统认出它…"))
            step(3, L("试音"), L("自动播一句，确认对方听得到"), done: installer.passed,
                 active: installer.state == .testing, activeText: L("正在试音…"))
            if let t = installer.test, !t.heard, installer.state != .testing {
                TestResultView(result: t)
            }
            if case .failed(let msg) = installer.state {
                Text(msg).font(.fee(.bodySecondary)).foregroundStyle(Palette.accentInk)
            }
            if !installer.busy {
                SoftButton(buttonTitle, dark: true) { installer.next() }
            }
        }
        .padding(.vertical, 12)
    }

    private var statusTag: String {
        if installer.busy { return L("进行中") }
        if !onDisk { return L("没装") }
        if !loaded { return L("系统还没认出") }
        return installer.test == nil ? L("还没试音") : L("没听到声音")
    }

    private var buttonTitle: String {
        if !onDisk { return L("一键安装") }
        if !loaded { return L("让系统认出它") }
        return installer.test == nil ? L("试音") : L("再试一次")
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, active: Bool, activeText: String) -> some View {
        // 红铅笔编号 + 手画方框，做完的打勾（样稿 round4 ⑧）
        HStack(alignment: .top, spacing: 10) {
            PencilNumber(n: n).frame(height: 22)
            PaperCheck(mark: done ? .done : active ? .running : .open).frame(height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(active ? activeText : title).font(.fee(.body, strong: true))
                    .foregroundStyle(done || active ? Palette.ink : Palette.secondary)
                    .frame(minHeight: 22)
                if !done && !active {
                    Text(detail).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}

struct TestResultView: View {
    let result: VirtualMicInstaller.TestResult
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if result.heard { HStack(alignment: .center, spacing: 2) {
                ForEach(Array(result.levels.enumerated()), id: \.offset) { _, l in
                    Rectangle().fill(result.heard ? Palette.accent : Palette.placeholder)
                        .frame(width: 3, height: max(3, CGFloat(min(1, l * 2.5)) * 24))
                }
            }
            .frame(height: 24) }
            if result.heard {
                (Text("对方会听到：") + Text(result.text.isEmpty ? L("一段声音") : "“\(result.text)”").bold())
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.ink)
            } else {
                Text(result.problem ?? L("虚拟麦克风未收到声音，请再试一次")).font(.fee(.bodySecondary)).foregroundStyle(Palette.accentInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // 听到了是绿便签，没听到是粉便签（方角、顶上一截胶带）
        .slipBackground(result.heard ? .good : .attention)
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var installer: VirtualMicInstaller

    /// 栏目分隔页的颜色，按顺序轮换（样稿 round3 › 设置）。
    static let tabColors = [Palette.stickyYellow, Palette.stickyPink, Palette.stickyGreen, Palette.stickySky,
                            Palette.kraft, Palette.hex(0xEBD9F0), Palette.paperShade]

    /// 设置窗口的大小（样稿 round3 › 设置）：左页目录、右页这一栏，右边伸出分隔页。
    static let size = CGSize(width: 900, height: 620)
    /// 两页在窗口里的位置：高 23 格；右边留 74pt 给分隔页。
    static let spread = CGRect(x: 36, y: 44, width: 790, height: PaperMetrics.pitch * 23)
    static let leftWidth: CGFloat = 250

    /// 目录和分隔页列出的栏目：诊断打开时才有。
    private var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0 != .diagnostics || settings.diagnostics }
    }

    var body: some View {
        // 皮面手帐翻到目录：左页手写目录，右页这一栏的设置，右边分隔页和目录一一对应
        //（诊断打开时七张，矮一点才排得进窗口高度）
        let seven = sections.count > 6
        PlannerBook(spread: Self.spread, leftWidth: Self.leftWidth,
                    tabs: sections.enumerated().map { i, s in
                        DividerTabs.Item(id: s.rawValue, title: s.tabTitle, color: Self.tabColors[i % Self.tabColors.count])
                    },
                    selected: model.settingsSection.rawValue, tabsTop: 24, tabHeight: seven ? 66 : 76, tabGap: 4,
                    pick: { id in if let s = SettingsSection(rawValue: id) { model.settingsSection = s } }) {
            contents
        } right: {
            ScrollView {
                page.environment(\.spreadRules, true)
            }
            .scrollTargetBehavior(RuleSnapScroll())
            .scrollIndicators(.never)
            // 右页的内容不盖到左页和纸边外
            .clipShape(Rectangle())
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .decor(.medium)
    }

    /// 左页：目录、角落里的菲比、诊断开关和版本。
    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录").font(.feeHero(26)).foregroundStyle(Palette.ink)
                .frame(height: PaperMetrics.pitch * 2)
            Color.clear.frame(height: PaperMetrics.pitch)
            ForEach(Array(sections.enumerated()), id: \.element) { i, s in
                PlannerTOCLine(title: s.title, page: i + 1, on: s == model.settingsSection,
                               action: { model.settingsSection = s }) {
                    if s == .speak && settings.speakEnabled && model.virtualMic == nil {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6).alignmentGuide(.lastTextBaseline) { $0[.bottom] + 3 }
                    }
                }
            }
            Spacer(minLength: 0)
            FeebeeDoodle(mood: .idle, size: 96)
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .frame(height: PaperMetrics.pitch * 4)
            // Diagnostics is for chasing slowness: off it leaves no trace in the table of contents.
            HStack(spacing: 6) {
                Toggle("诊断", isOn: Binding(get: { settings.diagnostics }, set: { model.setDiagnostics($0) }))
                    .toggleStyle(.paper).labelsHidden().tint(Palette.ink)
                Text("诊断").font(.fee(.label)).foregroundStyle(Palette.tertiary).fixedSize()
            }
            .frame(height: PaperMetrics.pitch)
            VersionLine(text: "\(appDisplayName) · \(L("版本 \(Self.version)"))", updates: model.updates,
                        showUpdate: { model.settingsSection = .records })
        }
        .padding(.leading, 26).padding(.trailing, 22)
        .padding(.top, PaperMetrics.pitch).padding(.bottom, PaperMetrics.pitch)
    }

    /// The current section without the scroll view (also drawn by the `settingsRender` debug command).
    var page: some View {
        VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
            HStack {
                Text(model.settingsSection.title).font(.fee(.title)).foregroundStyle(Palette.ink)
                    .frame(height: PaperMetrics.pitch * 2)
                Spacer()
                if model.settingsSection == .ai { AIServiceMenu(model: model, settings: settings) }
                if model.settingsSection == .speak {
                    Toggle("把我说的翻译给对方", isOn: Binding(get: { settings.speakEnabled }, set: { model.enableSpeaking($0) }))
                        .toggleStyle(.paper).labelsHidden().tint(Palette.ink)
                }
            }
            switch model.settingsSection {
            case .speak: speak
            case .overlay: overlay
            case .language: LanguageSettings(model: model, settings: settings)
            case .words: WordListSettings(model: model, settings: settings, vocabulary: model.vocabulary, ling: model.ling)
            case .records: records
            case .ai: AISettingsView(model: model, ling: model.ling, settings: settings)
            case .diagnostics: DiagnosticsView(diagnostics: model.diagnostics, service: settings.aiConfig)
            }
        }
        // 右页：红页边线在 64pt，字从 82pt 起；上沿空一格，标题占两格
        .padding(.leading, PaperMetrics.marginX + 18).padding(.trailing, 30).padding(.top, PaperMetrics.pitch).padding(.bottom, PaperMetrics.pitch * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 每项左边页边的红铅笔编号，这一栏从 1 数起；诊断页是图表，只有零星两项是设置行，不编号
        .overlayPreferenceValue(SettingsGutterKey.self) { anchors in
            if model.settingsSection != .diagnostics { SettingsGutterNumbers(anchors: anchors) }
        }
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    // MARK: Sections

    /// One card says whether the room hears you; it opens into a checklist only when something
    /// is wrong. Below it, plain settings: what you say with, and which microphones.
    private var speak: some View {
        VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
            if model.virtualMic == nil {
                SettingsCard { MicSetupCard(installer: installer, deviceName: nil) }
            } else {
                speakHealth
            }
            group(L("说话")) {
                SettingsRow(title: L("按住说话")) { ShortcutField(model: model, role: .talk) }
                // Hands-free runs only while listening, and pauses with the room mic on (`AppModel.handsFreeSetting`).
                SettingsRow(title: L("不用按键"),
                            detail: !settings.speakHandsFree ? L("开口就翻译，停顿 1 秒后说出去")
                                : settings.hearsRoom ? L("打开麦克风时暂停") : model.running ? L("开口就翻译，停顿 1 秒后说出去") : L("开始听会议后生效")) {
                    Toggle("不用按键", isOn: $settings.speakHandsFree)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("说\(settings.speakFromLang.name)，对方听到")) {
                    PillMenu(value: settings.speakTo == "room" ? L("跟随对方（\(targetName(model.speak.targetCode))）") : targetName(settings.speakTo),
                             options: [("room", L("跟随对方"))] + targetLanguages.map { ($0.code, $0.name) }) {
                        settings.speakTo = $0
                        model.objectWillChange.send()
                    }
                }
                VoiceSection(model: model, settings: settings, ling: model.ling)
            }
            if model.virtualMic != nil { micSettings }
        }
        .sheet(isPresented: $model.speakTestShown) {
            SpeakTestView(model: model, tester: model.speakTester) {
                if model.speakTester.busy { model.speakTester.cancel() }
                model.speakTestShown = false
            }
        }
        .sheet(item: $model.micGuide) { user in
            MicGuideView(model: model, bundleID: user.bundleID, name: user.name) { model.micGuide = nil }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        // 小节标题后接一道波浪线，下面的设置项直接写在纸上
        VStack(alignment: .leading, spacing: 0) {
            NotebookHeading(title: title)
            SettingsCard { content() }
        }
    }

    /// Something keeping the room from hearing you, with the one button that fixes it.
    private struct SpeakProblem: Identifiable {
        let id: String
        let text: String
        let button: String
        let action: () -> Void
    }

    private var speakProblems: [SpeakProblem] {
        var out: [SpeakProblem] = []
        if settings.speakEnabled && model.talkNeedsPermission {
            out.append(.init(id: "key", text: L("按键还需要“输入监控”权限"), button: L("去允许"), action: model.allowTalkKey))
        }
        // A switched-away or never-restored system mic matters even with speaking off.
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        switch model.systemMicState {
        case .notRestored:
            out.append(.init(id: "sysmic", text: L("系统麦克风还是 \(virtual)，别的软件听不到你"), button: L("还原"), action: model.restoreSystemMic))
        case .moved(let to):
            out.append(.init(id: "sysmic", text: L("系统麦克风被换成了 \(to)"), button: L("换回"), action: model.switchSystemMic))
        case .off where model.wantsSystemMic:
            out.append(.init(id: "sysmic", text: L("系统麦克风还没换成 \(virtual)"), button: L("切换"), action: model.switchSystemMic))
        default: break
        }
        if settings.speakEnabled {
            for user in model.micUsers where user.state.isOther {
                let text: String
                if case .otherMic(let mic) = user.state, !mic.isEmpty { text = L("\(user.name)还在用 \(mic)") }
                else { text = L("\(user.name)没选虚拟麦克风") }
                out.append(.init(id: user.bundleID, text: text, button: L("怎么改"), action: { model.micGuide = user }))
            }
        }
        return out
    }

    /// What already works, listed above the problems so the broken step reads in context.
    private var speakOK: [String] {
        var out = [L("虚拟麦克风 \(model.virtualMic?.name ?? "BlackHole 2ch")")]
        if case .switched = model.systemMicState { out.append(L("系统麦克风已换好，关掉时换回")) }
        if settings.speakEnabled {
            out += model.micUsers.filter { $0.state == .virtualMic }.map { L("\($0.name)已选虚拟麦克风") }
        }
        return out
    }

    private var speakHealth: some View {
        let problems = speakProblems
        let on = settings.speakEnabled
        let ok = problems.isEmpty
        // 直接写在纸上：状态一行；有问题时，做好的几项打勾，要处理的贴在一张粉便签上
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HealthMark(ok: ok, on: on)
                VStack(alignment: .leading, spacing: 0) {
                    Text(!ok ? L("线上的人听不到你") : on ? L("线上的人听得到你") : L("同声传译没打开"))
                        .font(.fee(.body, strong: true)).foregroundStyle(ok ? Palette.ink : Palette.accentInk)
                        .frame(minHeight: PaperMetrics.pitch)
                    Text(latencyLine).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: PaperMetrics.pitch)
                }
                Spacer(minLength: 8)
                SoftButton(L("试一句"), dark: ok, icon: "play.fill") { model.speakTestShown = true }
                    .help("说一句话，听对方听到的声音，看每一步花了多久")
            }
            if !ok {
                ForEach(speakOK, id: \.self) { line in
                    HStack(spacing: 12) {
                        HealthMark(ok: true, on: true)
                        Text(line).font(.fee(.body)).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .frame(minHeight: PaperMetrics.pitch)
                }
                speakProblemSlip(problems).padding(.top, PaperMetrics.pitch / 2)
            }
        }
    }

    private func speakProblemSlip(_ problems: [SpeakProblem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(problems) { p in
                HStack(spacing: 12) {
                    HealthMark(ok: false, on: true)
                    Text(p.text).font(.fee(.body)).foregroundStyle(Palette.accentInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    SoftButton(p.button, dark: true, action: p.action)
                }
                .frame(minHeight: 34)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slipBackground(.attention)
    }

    /// The last measured press, else what to expect.
    private var latencyLine: String {
        guard let v = model.lastSpeakLatency else {
            // Measured with 试一句: Ming's voice ~3 s after release, the Mac's ~1 s.
            let mac = model.voiceID(for: model.speak.targetCode)?.hasPrefix("system:") ?? true
            return mac ? L("按住说话，松开后约 1 秒，对方听到译文") : L("按住说话，松开后约 3 秒，对方听到译文")
        }
        return L("上次发言：松开后 \(String(format: "%.1f", v)) 秒，对方听到译文")
    }

    /// 麦克风: the virtual mic as the system default while speaking, the real mic Cicada records
    /// from, and where the spoken translation goes. Their state shows in the card above.
    private var micSettings: some View {
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        let inputs = model.systemMic.realInputs
        // A chosen mic that's unplugged reads as 自动 until it's back.
        let chosen = inputs.first { $0.uid == settings.speakMic }?.name
        let auto = model.systemMic.recordingDevice?.name
        return group(L("麦克风")) {
            SettingsRow(title: L("打开时把系统麦克风换成 \(virtual)")) {
                Toggle("自动切换系统麦克风", isOn: Binding(get: { settings.autoSystemMic }, set: { model.setAutoSystemMic($0) }))
                    .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
            }
            SettingsRow(title: L("\(appDisplayName)听你说话用")) {
                PillMenu(value: chosen ?? (auto.map { L("自动（\($0)）") } ?? L("自动")),
                         options: [("", L("自动"))] + inputs.map { ($0.uid, $0.name) }) {
                    settings.speakMic = $0
                }
            }
            // Only virtual mics: the translation is for the people online, never the speakers.
            SettingsRow(title: L("译文送到"), detail: L("只给线上的人听，不从扬声器放"), divider: false) {
                PillMenu(value: outputName,
                         options: [("", L("虚拟麦克风（自动）"))] + model.outputs.filter(\.isVirtualMic).map { ($0.uid, $0.name) }) {
                    settings.speakOutput = $0
                    model.applySystemMic()
                }
            }
        }
    }

    private var outputName: String {
        if settings.speakOutput.isEmpty { return L("虚拟麦克风（自动）") }
        return model.outputs.first { $0.uid == settings.speakOutput && $0.isVirtualMic }?.name ?? L("虚拟麦克风（自动）")
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
            SettingsCard {
                SettingsRow(title: L("听的时候显示"), detail: L("选择任意模式都会正常保存记录、生成纪要")) {
                    Segments(options: [("notes", L("实时纪要")), ("bar", L("字幕条")), ("none", L("不显示"))],
                             value: settings.displayMode) { model.setDisplayMode($0) }
                }
                SettingsRow(title: L("切换显示方式"), detail: model.toggleKeyTaken ? L("被其他应用占用了，点右边换一个") : L("实时纪要 → 字幕条 → 不显示"), divider: false) {
                    ShortcutField(model: model, role: .toggle)
                }
            }
            // 手帐的样子（第七轮样稿 ①②）：封皮颜色、内页纸、台灯模式
            group(L("手帐")) {
                SettingsRow(title: L("封皮")) {
                    HStack(spacing: 10) {
                        ForEach(CoverTheme.allCases, id: \.rawValue) { c in
                            Button { settings.coverColor = c.rawValue } label: {
                                Circle().fill(Palette.hex(c.mid)).frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Palette.paper, lineWidth: 2).padding(-2))
                                    .overlay(Circle().stroke(settings.coverColor == c.rawValue ? Palette.link : .clear, lineWidth: 1.5).padding(-4))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain).help(c.name)
                        }
                    }
                }
                SettingsRow(title: L("内页")) {
                    Segments(options: [("ruled", L("横线")), ("grid", L("方格")), ("dot", L("点阵"))], value: settings.paperPattern) { settings.paperPattern = $0 }
                }
                SettingsRow(title: L("台灯模式"), detail: L("夜里把纸调暗；跟随系统时，系统是深色就自动打开"), divider: false) {
                    Segments(options: [("system", L("跟随系统")), ("on", L("总是开")), ("off", L("关"))], value: settings.lampMode) { settings.lampMode = $0 }
                }
            }
            group(L("实时纪要")) {
                SettingsRow(title: L("共享屏幕时让对方看到"), detail: L("录屏也一样；关着时只有你看得到纪要窗口"), divider: false,
                            mark: AnyView(CapturableMark(on: settings.notesCapturable, size: 8).frame(width: 16, height: 16))) {
                    Toggle("共享屏幕时让对方看到", isOn: Binding(get: { settings.notesCapturable }, set: { model.setNotesCapturable($0) }))
                        .toggleStyle(.paper).labelsHidden().tint(Palette.accent)
                }
            }
            group(L("字幕条")) {
                SettingsRow(title: L("字幕条显示时机")) {
                    overlayAutoSegments(model: model)
                }
                if settings.overlayAuto {
                    SettingsRow(title: L("安静多久后收起")) {
                        hideAfterSegments(settings: settings)
                    }
                }
                SettingsRow(title: L("字幕条样式")) {
                    Segments(options: [("dark", L("深色")), ("paper", L("纸条"))], value: settings.subtitleSkin) { settings.subtitleSkin = $0 }
                }
                SettingsRow(title: L("位置和大小"), detail: L("鼠标悬停可拖动位置，拖拽右下角可缩放大小"), divider: false) {
                    SoftButton(L("恢复默认")) { model.overlay.resetPosition() }
                }
            }
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
            SettingsCard {
                SettingsRow(title: L("保存会议录音"), detail: L("只存在这台 Mac 上")) {
                    Toggle("保存会议录音", isOn: $settings.recordAudio)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("开始听时打开麦克风"), detail: L("关掉后只听电脑声音；开会时再手动打开")) {
                    Toggle("开始听时打开麦克风", isOn: $settings.autoMicOnStart)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("说话人识别"), detail: L("按声音标出说话人 1、2…，只在这台 Mac 上处理")) {
                    Toggle("说话人识别", isOn: $settings.speakerVoices)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("每句都显示说话人"), detail: L("连续同一个人说话时也重复标出，不再只在换人时标")) {
                    Toggle("每句都显示说话人", isOn: $settings.speakerEveryLine)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                        .disabled(!settings.speakerVoices)
                }
                SettingsRow(title: L("记住说话人"), detail: L("按本机声纹认出以前见过的人；不会上传声音")) {
                    Toggle("记住说话人", isOn: $settings.speakerMemory)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("人员库"), detail: L("\(model.speakerProfiles.count) 个人 · 声纹和备注")) {
                    SoftButton(L("管理")) { model.speakerLibraryShown = true }
                }
                SettingsRow(title: L("记录文件夹"), divider: false) {
                    SoftButton(L("打开")) { NSWorkspace.shared.open(model.store.root) }
                }
            }
            group(L("会后存一份")) {
                FolderExportSettings(model: model, settings: settings, exporter: model.folderExport)
            }
            group(L("导入的文件")) {
                SettingsRow(title: L("文件里说的"), detail: L("译成“翻译成”里的语言")) {
                    Picker("文件里说的", selection: $settings.importLanguage) {
                        Text("自动识别").tag("auto")
                        ForEach(sourceLanguages, id: \.locale) { Text($0.name).tag($0.locale) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(title: L("转完后生成纪要"),
                            detail: Recognition.cloudOnly ? L("导入转写和生成纪要都需要 Ling key") : L("需要 Ling key；没有也能转出文字记录"),
                            divider: false) {
                    Toggle("转完后生成纪要", isOn: $settings.importNotes)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
            }
            group(L("结束会议")) {
                SettingsRow(title: L("会议应用挂断后结束"), detail: L("Zoom、腾讯会议、飞书、Teams 等")) {
                    Toggle("会议应用挂断后结束", isOn: $settings.endWithApp)
                        .toggleStyle(.paper).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("没人说话时"), detail: L("按识别出的话算，背景音乐不算"), divider: settings.silenceEnd != "off") {
                    Segments(options: [("prompt", L("提醒后结束")), ("end", L("直接结束")), ("off", L("一直记录"))],
                             value: settings.silenceEnd) { settings.silenceEnd = $0 }
                }
                if settings.silenceEnd != "off" {
                    SettingsRow(title: L("多久算没人说话"), divider: false) {
                        Segments(options: [5.0, 10, 15, 30].map { (String(Int($0)), L("\(Int($0)) 分钟")) },
                                 value: String(Int(settings.silenceMinutes))) { settings.silenceMinutes = Double($0) ?? 10 }
                    }
                }
            }
            AppRows(updates: model.updates, loginItem: model.loginItem, model: model)
        }
        .sheet(isPresented: $model.speakerLibraryShown) {
            SpeakerLibraryView(model: model)
        }
    }
}
