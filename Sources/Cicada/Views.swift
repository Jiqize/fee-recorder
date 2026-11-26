import AppKit
import SwiftUI

/// A service in trouble, said the same way wherever it shows: a dot, what waits for what · what
/// still works, and at most one action. Colour sits in the dot only, so a passing wait doesn't
/// read as a fault: yellow waits and comes back by itself, red needs you, grey is just so you know.
struct StatusLine: View {
    enum Tone { case waiting, needsYou, info }
    let tone: Tone
    let text: String
    var action: (title: String, run: () -> Void)? = nil

    /// #C98A00: the warn ink is too dark to tell from the text at 6 pt.
    static let waitingDot = Palette.hex(0xC98A00)

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tone == .waiting ? Self.waitingDot : tone == .needsYou ? Palette.error : Palette.tertiary)
                .frame(width: 6, height: 6)
            Text(text).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action.run) {
                    Text(action.title).font(.fee(.bodySecondary, strong: true)).foregroundStyle(Palette.ink)
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain).fixedSize()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(minHeight: 36)
        .slipBackground(tone == .needsYou ? .attention : .note)
    }
}

struct LogoTile: View {
    var size: CGFloat = 34
    var body: some View { BrandMark(size: size) }
}

typealias ChoiceOption = (id: String, title: String)

/// A gray rounded row that opens a menu, used for the language choices.
struct ChoiceRow: View {
    let label: String
    let value: String
    var badge: String? = nil
    /// 40pt instead of 44, for the menu bar panel where four rows sit one above the other.
    var compact = false
    /// Groups the menu separates; a header is its grey section title.
    let sections: [(header: String?, options: [ChoiceOption])]
    let onPick: (String) -> Void

    init(label: String, value: String, badge: String? = nil, compact: Bool = false,
         sections: [(header: String?, options: [ChoiceOption])], onPick: @escaping (String) -> Void) {
        self.label = label; self.value = value; self.badge = badge; self.compact = compact
        self.sections = sections.filter { !$0.options.isEmpty }
        self.onPick = onPick
    }

    init(label: String, value: String, badge: String? = nil, compact: Bool = false,
         options: [ChoiceOption], onPick: @escaping (String) -> Void) {
        self.init(label: label, value: value, badge: badge, compact: compact, sections: [(nil, options)], onPick: onPick)
    }

    var body: some View {
        Menu {
            // Sections, not Dividers: the menu draws the separators itself, and a Divider next to
            // a headed Section would draw a second one.
            ForEach(sections.indices, id: \.self) { i in
                if let header = sections[i].header {
                    Section(header) { buttons(sections[i].options) }
                } else {
                    Section { buttons(sections[i].options) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                // 手帐字体比系统字宽：「Translate to」一行放不下就缩一点，不折成两行
                Text(label).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: uiIsChinese ? 44 : 80, alignment: .leading)
                Text(value).font(.fee(.body, strong: true)).foregroundStyle(Palette.ink).lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.fee(.label, strong: true))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(Rectangle().stroke(Palette.accentInk, lineWidth: 1.2))
                        .tilted(-2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.icon(10, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: compact ? 40 : 44)
            // 写在纸上的一行，下面一道细线（第四轮样稿 ③）
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func buttons(_ options: [ChoiceOption]) -> some View {
        ForEach(options, id: \.id) { o in
            Button(o.title) { onPick(o.id) }
        }
    }
}

// MARK: - Menu bar panel

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    /// Languages without a speech model on this Mac sit in their own group under one line saying
    /// picking one downloads it, rather than a suffix on every row.
    private var sourceSections: [(header: String?, options: [ChoiceOption])] {
        let auto = model.candidates.map(\.name).joined(separator: "、")
        let ready = sourceLanguages.filter { model.installed.isEmpty || model.installed.contains($0.locale) }
        let missing = sourceLanguages.filter { !ready.contains($0) }
        return [
            (nil, [("auto", auto.isEmpty ? L("自动识别") : L("自动识别（\(auto)）"))]),
            (nil, ready.map { ($0.locale, $0.name) }),
            // macOS 14/15 can't download one: the language is added to Dictation in System Settings.
            (Recognition.legacy ? L("要先加进系统的听写语言") : L("选中后自动下载语音模型"), missing.map { ($0.locale, $0.name) }),
        ]
    }

    private var targetOptions: [(id: String, title: String)] {
        [("system", L("跟随系统（\(settings.systemTargetDescription())）"))] + targetLanguages.map { ($0.code, $0.name) }
    }

    private var heardValue: (String, String?) {
        switch settings.sourceMode {
        case .fixed(let l): return (l.name, nil)
        case .auto: return (model.listen.activeLang?.name ?? L("自动"), L("自动识别"))
        }
    }

    /// The panel's natural height, measured; past what the screen can show it scrolls.
    @State private var contentHeight: CGFloat = 0

    /// A popover taller than the screen is cut off at the top (a small screen, the menu bar on it).
    private var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 900) - 24 }

    var body: some View {
        let measured = panel.background(GeometryReader { g in
            Color.clear.preference(key: PanelHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { contentHeight = $0 }
        if contentHeight > maxHeight {
            ScrollView { measured }.frame(width: 320, height: maxHeight).background(Palette.paper).decor(.low)
        } else {
            measured.decor(.low)
        }
    }

    /// 面板顶部菲比的样子：在听 / 在写纪要 / 在打盹。
    private var mood: FeebeeMood {
        FeebeeMood.of(live: model.running, notesState: model.notes.state, hasNotes: !model.notes.notes.isEmpty, final: model.notes.notes.final)
    }

    /// 面板顶上一截皮面（第三轮样稿 › 菜单栏面板）：菲比、应用名、状态，右边一支横着的小笔当「开始听」。
    private var band: some View {
        HStack(spacing: 10) {
            FeebeeView(mood: mood, size: 40)
                .padding(3).background(RoundedRectangle(cornerRadius: 9).fill(Palette.paper))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appDisplayName).font(.fee(.section)).foregroundStyle(Palette.onLeather)
                    if let dev = DevBuild.label {
                        Text("DEV").font(.fee(.caption, strong: true)).foregroundStyle(Palette.penBlack)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Palette.onLeather))
                            .help(dev)
                    }
                }
                if let dev = DevBuild.label {
                    Text(dev).font(.fee(.label).monospaced()).foregroundStyle(Palette.onLeather.opacity(0.75)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Circle().fill(model.running ? Palette.accent : Palette.onLeather.opacity(0.5)).frame(width: 7, height: 7)
                    // Two lines: "English (detecting…) → 简体中文" doesn't fit one beside the switch.
                    Text(model.running ? model.summary : model.autoEnded ? L("会议已自动结束") : L("已暂停"))
                        .font(.fee(.bodySecondary)).foregroundStyle(Palette.onLeather.opacity(0.9)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PanelImportLine(importer: model.importer, store: model.store)
            }
            Spacer(minLength: 4)
            Button { model.setRunning(!model.running) } label: {
                HStack(spacing: 0) {
                    UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11, bottomTrailingRadius: 3, topTrailingRadius: 3)
                        .fill(LinearGradient(colors: [Palette.accent, Palette.error], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .shadow(color: Palette.accent.opacity(model.running ? 0.6 : 0), radius: 6)
                    Text(model.running ? L("结束") : L("开始听"))
                        .font(.fee(.label, strong: true)).foregroundStyle(Palette.penLabel)
                        .padding(.leading, 8).padding(.trailing, 10).frame(height: 22)
                        .background(UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                            .fill(LinearGradient(colors: [Palette.penGrey, Palette.penBlack], startPoint: .top, endPoint: .bottom)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(model.running ? L("结束") : L("开始听"))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(LeatherCover())
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
        band
        VStack(alignment: .leading, spacing: 14) {
            if let p = model.ending { MeetingEndingStrip(model: model, pending: p, compact: true) }
            // In subtitle-bar mode this is where the bar sends you to pick.
            if model.running { LanguageNotice(model: model) }
            if model.hybridMicDenied { hybridMicStrip }
            if let next = model.roomMicLost { roomMicLostStrip(next) }
            AIServiceStrip(model: model, ling: model.ling)
            // Right under the header: below the settings it was easy to miss.
            UpdateBanner(updates: model.updates, model: model)

            VStack(spacing: 6) {
                ChoiceRow(label: L("听到"), value: heardValue.0, badge: heardValue.1, compact: true, sections: sourceSections) {
                    model.sourceSelection = $0
                }
                ChoiceRow(label: L("翻译成"),
                          value: targetName(model.listen.resolvedTarget),
                          // "Follow system" leaves no room for the language name in the panel.
                          badge: settings.target == "system" ? (uiIsChinese ? L("跟随系统") : L("系统")) : nil,
                          compact: true, options: targetOptions) {
                    model.targetSelection = $0
                }
            }

            micRow

            Divider()

            speakSection
            if let strip = systemMicStrip {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strip.title).font(.fee(.bodySecondary)).foregroundStyle(Palette.accentInk)
                        Text(strip.detail).font(.fee(.label)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    SoftButton(strip.button, dark: true, action: strip.action)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .slipBackground(.attention)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("显示方式").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                    Spacer()
                    HStack(spacing: 5) {
                        KeyCap(settings.toggleKey.display)
                        Text("轮换").foregroundStyle(Palette.tertiary)
                    }
                    .font(.fee(.label))
                    .help(L("切换显示方式"))
                }
                HStack(spacing: 8) {
                    ForEach(DisplayTile.modes, id: \.self) { mode in
                        DisplayTile(mode: mode, selected: settings.displayMode == mode, caption: tileCaption(mode)) {
                            pickDisplay(mode)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if settings.displayMode != "notes" || !model.ling.hasKey { displayCard }
                PanelTodoLine(model: model, store: model.store, inbox: model.todoInbox)
            }

            Divider()

            footer
        }
        .padding(16)
        }
        .frame(width: 320)
        .background(Palette.paper)
    }

    /// The panel's actions as three equal buttons, so they read as buttons rather than loose
    /// grey words. No version line: an update shows its own strip above, and 设置 › 会议记录 checks.
    private var footer: some View {
        // 底部入口是带虚线的字
        HStack(spacing: 0) {
            PanelAction(L("会议记录"), symbol: "doc.text") { model.openMainWindow?() }
            Spacer()
            PanelAction(L("导入文件…"), symbol: "square.and.arrow.down") { model.chooseImportFiles() }
            Spacer()
            PanelAction(L("退出"), symbol: "power", quiet: true) { NSApp.terminate(nil) }
        }
    }

    /// The picked 实时纪要 tile is also the notes window's open/close switch, so the panel
    /// needs no separate row for it.
    private func pickDisplay(_ mode: String) {
        if mode == "notes", settings.displayMode == "notes" {
            model.notesShown ? model.hideNotesWindow() : model.openNotesWindow()
        } else {
            model.setDisplayMode(mode)
        }
    }

    private func tileCaption(_ mode: String) -> String? {
        guard mode == "notes", settings.displayMode == "notes" else { return nil }
        return model.notesShown ? L("再点收起") : L("再点打开")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension MenuPanelView {
    /// 电脑和会议室 without the microphone: the Mac's side is still recorded.
    var hybridMicStrip: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("听会议室要先允许麦克风").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                Text("电脑声音照常在记").font(.fee(.label)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            SoftButton(L("去设置"), dark: true) { model.openMicrophoneSettings() }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .slipBackground(.attention)
    }
}

extension MenuPanelView {
    /// 外接麦克风断开了: what Cicada did instead. Goes away by itself.
    func roomMicLostStrip(_ next: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("外接麦克风断开了").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
            Text(next).font(.fee(.label)).foregroundStyle(Palette.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .slipBackground(.attention)
    }
}

/// 「显示方式」下面：我的待办今天到期 / 逾期的有几条，点了打开待办板；都没有就不显示。
struct PanelTodoLine: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore
    @ObservedObject var inbox: TodoInbox

    var body: some View {
        let mine = TodoBoard.items(sessions: store.sessions, inbox: inbox.items).filter { TodoBoard.isMine($0.item) }
        let c = TodoBoard.counts(mine, today: Date())
        let parts = [c.dueToday > 0 ? L("今天到期 \(c.dueToday) 条") : nil, c.overdue > 0 ? L("逾期 \(c.overdue) 条") : nil].compactMap { $0 }
        if !parts.isEmpty {
            Button {
                model.todoBoardShown = true
                model.openMainWindow?()
            } label: {
                HStack(spacing: 4) {
                    Text(L("待办：") + parts.joined(separator: " · ")).foregroundStyle(c.overdue > 0 ? Palette.error : Palette.ink)
                    Spacer(minLength: 4)
                    Text("›").foregroundStyle(Palette.secondary)
                }
                .font(.fee(.bodySecondary)).lineLimit(1)
                // 一条粉纸条（第三轮样稿 › 菜单栏面板）
                .padding(.horizontal, 10).frame(height: 28)
                .background(Rectangle().fill(Palette.stickyPink))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("打开待办板"))
        }
    }
}

/// Under the panel's status: the file being transcribed in the background, if any.
struct PanelImportLine: View {
    @ObservedObject var importer: FileImporter
    @ObservedObject var store: SessionStore

    var body: some View {
        if let job = importer.current {
            let name = store.session(job.id)?.displayTitle ?? job.url.lastPathComponent
            HStack(spacing: 6) {
                ProgressView(value: importer.progress).progressViewStyle(.circular).controlSize(.mini).tint(Palette.ink)
                    .frame(width: 10, height: 10)
                Text(importer.queue.isEmpty ? L("后台转写 \(name) · \(Int(importer.progress * 100))%")
                     : L("后台转写 \(name) · \(Int(importer.progress * 100))%，还有 \(importer.queue.count) 个"))
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

extension MenuPanelView {
    /// The settings of the chosen display mode only, so switching modes swaps one card
    /// instead of reshuffling the section.
    @ViewBuilder var displayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch settings.displayMode {
            case "bar":
                cardRow(L("什么时候出现")) {
                    overlayAutoSegments(model: model, fill: uiIsChinese, track: Palette.line).frame(width: uiIsChinese ? segmentWidth : nil)
                }
                if settings.overlayAuto {
                    cardRow(L("安静多久后收起")) {
                        hideAfterSegments(settings: settings, fill: uiIsChinese, track: Palette.line).frame(width: uiIsChinese ? segmentWidth : nil)
                    }
                }
            case "none":
                Text("屏幕上不出字幕，文字记录照常保存")
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                // Shown only without a Ling key: the notes window itself opens and closes from the tile.
                Text(Recognition.cloudOnly ? L("填入 Ling key 后才能识别语音、出字幕和纪要") : L("填入 API key 后可生成纪要；文字记录照常保存"))
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slipBackground(.note)
    }

    /// Both 字幕条 choices share one width so their right edges line up; English sizes to fit and may stack.
    private var segmentWidth: CGFloat { 160 }

    /// A label and its control on one line, or stacked when the English runs too wide.
    private func cardRow<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
        let label = Text(title).font(.fee(.bodySecondary)).foregroundStyle(Palette.ink)
        let c = control()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { label; Spacer(minLength: 8); c }
            VStack(alignment: .leading, spacing: 6) { label; c }
        }
    }

    var systemMicStrip: (title: String, detail: String, button: String, action: () -> Void)? {
        let virtual = model.virtualMic?.name ?? "BlackHole 2ch"
        switch model.systemMicState {
        case .notRestored:
            return (L("系统麦克风还是 \(virtual)"), L("别的软件现在听不到你说话"), L("还原"), model.restoreSystemMic)
        case .moved(let to):
            return (L("系统麦克风被换成了 \(to)"), L("跟随系统的网页听不到译文"), L("换回"), model.switchSystemMic)
        default:
            return nil
        }
    }
}

// MARK: - 麦克风 in the panel

extension MenuPanelView {
    /// 打开麦克风: the people in the room join the meeting the Mac is hearing.
    var micRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("麦克风").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                Text(model.micOn ? L("桌边的人说话也会记下") : L("关着 · 只听电脑声音"))
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            MicButton(model: model, settings: settings, inHeader: false)
        }
    }
}

/// 打开麦克风 / 关闭麦克风, the same switch in the panel and the notes window: a paper switch
/// (第六轮样稿 ④). In the notes window's header it says 麦克风 beside it, since the panel's row
/// label isn't there. The dashed ⌄ next to it picks the microphone, where the user is when the room
/// sounds wrong rather than in Settings.
struct MicButton: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let inHeader: Bool

    var body: some View {
        let on = model.micOn
        HStack(spacing: 6) {
            chooser
            Button { model.setMic(!on) } label: {
                HStack(spacing: 6) {
                    if inHeader { Text("麦克风").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).lineLimit(1).fixedSize() }
                    PaperSwitch(on: on)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? L("关闭麦克风") : L("打开麦克风"))
            .help(on ? L("关闭麦克风") : L("打开麦克风"))
        }
        .fixedSize()
    }

    /// The room's microphones, with 自动 first naming the one it would take. A chosen one that is
    /// unplugged shows as 自动 until it is back.
    private var chooser: some View {
        let choices = AudioDevices.roomMicChoices()
        let chosen = choices.contains { $0.device.uid == settings.roomMicUID } ? settings.roomMicUID : ""
        let auto = AudioDevices.roomMic()?.name
        return Menu {
            Picker(L("会议室用哪个麦克风"), selection: Binding(get: { chosen }, set: { model.setRoomMic($0) })) {
                Text(auto.map { L("自动（\($0)）") } ?? L("自动")).tag("")
                ForEach(choices, id: \.device.uid) { c in
                    // A headset hears its wearer, not the table: fine for your own notes, so say it.
                    Text(c.bluetooth ? L("\(c.device.name)（只听得到戴的人）") : c.device.name).tag(c.device.uid)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // 带虚线的一个小 ⌄（带虚线的字 = 可点）
            NotebookWord { Image(systemName: "chevron.down").font(.icon(9, weight: .bold)) }
                .frame(width: 16, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(L("选择麦克风"))
        .help(L("选择麦克风"))
    }
}

/// 纸上的开关（第六轮样稿 ④）：直角小方框、1.5pt 墨线、纸色底，里面一个方滑块；
/// 开着时滑到右边，框变 `stickyGreen`、滑块 `ok`。菜单栏面板和纪要窗页眉共用，本身不歪、不贴胶带。
struct PaperSwitch: View {
    let on: Bool
    /// 问过才打开（同声传译第一次）：画成开着，但滑块是灰的。
    var pending = false

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Rectangle().fill(on && !pending ? Palette.stickyGreen : Palette.paper)
            Rectangle().fill(pending ? Palette.tertiary : on ? Palette.ok : Palette.ink)
                .frame(width: 11, height: 11).padding(.horizontal, 4)
        }
        .frame(width: 34, height: 20)
        .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// `Toggle` drawn as a `PaperSwitch` (the panel's 同声传译).
struct PaperSwitchStyle: ToggleStyle {
    var pending = false
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            PaperSwitch(on: configuration.isOn, pending: pending).frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - 同声传译 in the panel

extension MenuPanelView {
    private var speakFrom: String { settings.speakFromLang.name }
    private var speakTarget: String { targetName(model.speak.targetCode) }
    private var talkKeyName: String { settings.talkKey.display }

    /// What the switch changes, on hover and in the one-time question.
    private var speakMicLine: String {
        if settings.listensToRoom { return L("译文从扬声器念出来") }
        guard let mic = model.virtualMic?.name else { return L("先装好虚拟麦克风，对方才听得到") }
        return settings.autoSystemMic ? L("系统麦克风换成 \(mic)") : L("译文送进 \(mic)")
    }

    private var speakHelp: String {
        L("打开：\(speakMicLine)，按住 \(talkKeyName) 说话\n关掉：全部还原")
    }

    /// 同声传译: the first time the switch asks in place what it changes; once on, the talk key is
    /// the section, and whatever stops the room hearing you shows on it.
    var speakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同声传译").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                    if !settings.speakEnabled && !model.speakAsking {
                        Text("说\(speakFrom) → \(speakTarget)").font(.fee(.bodySecondary))
                            .foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if settings.speakEnabled {
                    Button("设置") { model.openSettings(.speak) }
                        .buttonStyle(.plain).font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
                }
                Toggle("同声传译", isOn: Binding(get: { settings.speakEnabled || model.speakAsking }, set: setSpeaking))
                    .toggleStyle(PaperSwitchStyle(pending: model.speakAsking)).labelsHidden()
                    .help(speakHelp)
            }
            if model.speakAsking {
                speakQuestion
            } else if settings.speakEnabled {
                talkCard
                if model.lastSpeakLatency == nil, model.virtualMic != nil, !settings.listensToRoom, model.speakPhase == .idle {
                    Button("先试一句 →") { model.openSettings(.speak); model.speakTestShown = true }
                        .buttonStyle(.plain).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func setSpeaking(_ on: Bool) {
        if on && !settings.speakConfirmed { model.speakAsking = true; return }
        model.speakAsking = false
        if on != settings.speakEnabled { model.enableSpeaking(on) }
    }

    /// Asked once: switching the system mic is a change people should hear about before it happens.
    private var speakQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("打开后：").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
            questionLine(1) { Text(speakMicLine) }
            questionLine(2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { Text("按住"); KeyCap(talkKeyName); Text("说话，松开后播出译文") }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) { Text("按住"); KeyCap(talkKeyName) }
                        Text("说话，松开后播出译文")
                    }
                }
            }
            questionLine(3) { Text("关掉后全部还原") }
            HStack(spacing: 8) {
                Spacer()
                SoftButton(L("取消"), onGrey: true) { model.speakAsking = false }
                SoftButton(L("好，打开"), dark: true) { model.speakAsking = false; model.enableSpeaking(true) }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slipBackground(.note)
    }

    private func questionLine<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").foregroundStyle(Palette.tertiary).frame(width: 12, alignment: .leading)
            content().foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.fee(.bodySecondary))
    }

    /// The first thing keeping the room from hearing you, with the one action that fixes it.
    private var talkProblem: (text: String, button: String, action: () -> Void)? {
        if model.talkNeedsPermission {
            return (L("按键还需要“输入监控”权限"), L("去允许"), model.allowTalkKey)
        }
        // In 会议室 the translation is read out loud: no virtual mic, no meeting app to set up.
        if settings.listensToRoom { return nil }
        if model.virtualMic == nil {
            return (L("虚拟麦克风还没装好"), L("设置"), { model.openSettings(.speak) })
        }
        if let user = model.micUsers.first(where: { $0.state.isOther }) {
            let text: String
            if case .otherMic(let mic) = user.state, !mic.isEmpty { text = L("\(user.name)还在用 \(mic)") }
            else { text = L("\(user.name)没选虚拟麦克风") }
            return (text, L("怎么改"), { model.showMicGuide(user) })
        }
        return nil
    }

    private var talkCard: some View {
        let phase = model.speakPhase
        let live = phase != .idle
        let problem = live ? nil : talkProblem
        let title: String = switch phase {
        case .idle: L("按住说\(speakFrom)")
        case .listening: L("正在听…")
        case .translating: L("正在翻译…")
        case .speaking: L("正在播出…")
        }
        let hearer = model.micUsers.first { $0.state == .virtualMic }?.name
        let detail = phase == .listening ? L("松开后播出\(speakTarget)")
            : live ? L("说\(speakFrom) → \(speakTarget)")
            : settings.listensToRoom ? L("扬声器念出\(speakTarget)")
            : hearer.map { L("对方听到 \(speakTarget) · \($0)") } ?? L("对方听到 \(speakTarget)")
        return HStack(spacing: 12) {
            TalkKeyCap(text: talkKeyName, pressed: phase == .listening, live: live)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.fee(.body, strong: true))
                    .foregroundStyle(live ? Palette.accentInk : Palette.ink).lineLimit(1)
                if let problem {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(problem.text).foregroundStyle(Palette.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(problem.button, action: problem.action)
                            .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(Palette.accentInk).fixedSize()
                    }
                    .font(.fee(.label))
                } else {
                    Text(detail).font(.fee(.label)).foregroundStyle(Palette.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if !live {
                Circle().fill(problem == nil ? Palette.ok : Palette.accent).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(live ? Palette.accentWash : Color.white))
        .overlay(Rectangle().stroke(live ? Palette.accent : Palette.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: live)
    }
}

/// The talk key drawn as a key: raised while it waits, pressed down while you hold it.
struct TalkKeyCap: View {
    let text: String
    let pressed: Bool
    let live: Bool
    var body: some View {
        Text(text)
            .font(.fee(.bodySecondary, strong: true))
            .foregroundStyle(live ? Palette.accentInk : Palette.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 32)
            .background(Rectangle().fill(Color.white))
            .overlay(Rectangle().stroke(live ? Palette.accent : Palette.placeholder, lineWidth: 1))
            .background(Rectangle().fill(live ? Palette.accent : Palette.placeholder).offset(y: pressed ? 0 : 2))
            .offset(y: pressed ? 2 : 0)
            .padding(.bottom, 2)
    }
}

/// One of 实时纪要 / 字幕条 / 不显示 in the menu bar panel: a small picture of what shows on screen.
struct DisplayTile: View {
    static let modes = ["notes", "bar", "none"]
    let mode: String
    let selected: Bool
    /// Under the picked tile's name: what clicking it again does.
    var caption: String? = nil
    let action: () -> Void

    private var title: String {
        switch mode {
        case "bar": return L("字幕条")
        case "none": return L("不显示")
        default: return L("实时纪要")
        }
    }

    /// 三张小便签（第六轮样稿 ④）：实时纪要黄、字幕条蓝、不显示是纸上一个虚线框。
    private var color: Color {
        switch mode {
        case "bar": return Palette.stickySky
        case "none": return Palette.paper
        default: return Palette.stickyYellow
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                glyph.frame(height: 20).opacity(selected ? 1 : 0.7)
                Text(title)
                    .font(.fee(.bodySecondary, strong: selected))
                    .foregroundStyle(selected ? Palette.ink : Palette.body)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.top, -2)
                }
            }
            .padding(.top, 8).padding(.bottom, 6).padding(.horizontal, 8)
            // The row grows by the caption; every tile takes the row's height.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Rectangle().fill(color))
            .overlay {
                if mode == "none" {
                    Rectangle().strokeBorder(selected ? Palette.ink : Palette.placeholder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            // 选中的那张歪 −2°、阴影深一点、顶上一截牛皮纸胶带；虚线框不投影
            .compositingGroup()
            .shadow(color: mode == "none" ? .clear : Palette.hex(0x3A2A18, opacity: selected ? 0.3 : 0.2),
                    radius: selected ? 4 : 2, x: selected ? 2 : 1, y: selected ? 4 : 2)
            .overlay(alignment: .top) { if selected { Tape(style: .kraft, width: 36).scaleEffect(y: 0.7).offset(y: -7) } }
            .rotationEffect(.degrees(selected ? -2 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private let frameLine = Palette.placeholder

    @ViewBuilder private var glyph: some View {
        switch mode {
        case "bar":
            RoundedRectangle(cornerRadius: 4).fill(Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(frameLine, lineWidth: 1))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.ink).frame(width: 20, height: 5).padding(.bottom, 2.5)
                }
                .frame(width: 30, height: 20)
        case "none":
            RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.tertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 30, height: 20)
        default:
            VStack(alignment: .leading, spacing: 2.5) {
                Capsule().fill(Palette.ink).frame(width: 14, height: 2.5)
                Capsule().fill(frameLine).frame(width: 18, height: 2.5)
                Capsule().fill(frameLine).frame(width: 16, height: 2.5)
            }
            .padding(4)
            .frame(width: 28, height: 20, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(frameLine, lineWidth: 1))
        }
    }
}

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.fee(.label, strong: true))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 6).padding(.vertical, 1)
            // 纸做的小键帽：纸色底、细边、下面一道硬阴影
            .background(Rectangle().fill(Palette.paperShade))
            .overlay(Rectangle().stroke(Palette.placeholder, lineWidth: 1))
            .background(Rectangle().fill(Palette.placeholder).offset(x: 1.5, y: 1.5))
    }
}

/// One of the panel's footer buttons: an icon over its name on a grey tile.
struct PanelAction: View {
    let title: String
    let symbol: String
    /// 退出: grey ink, it ends the app rather than opening something.
    var quiet = false
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, symbol: String, quiet: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.quiet = quiet; self.action = action
    }

    var body: some View {
        // 带虚线的字（样稿 › 菜单栏面板）；图标留着给读屏和悬停提示用不上，所以只画字
        Button(action: action) {
            NotebookWord { Text(title).lineLimit(1).foregroundStyle(quiet ? Palette.secondary : hover ? Palette.ink : Palette.body) }
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .help(title)
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Main window

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var importer: FileImporter
    @StateObject private var player = RecordingPlayer()
    @State private var dropping = false
    @State private var selection: String?
    @State private var query = ""
    /// Which of the shown record's matches the search is on (#33: a search opens the line, not just the meeting).
    @State private var matchIndex = 0
    @State private var view = "both"
    @State private var tab = "notes"
    @State private var jumpTo: Double?
    /// A topic's time picked in the notes, for the bilingual column beside them.
    @State private var quoteJump: Double?
    @State private var detailWidth: CGFloat = 0
    /// The title block has scrolled away: a slim bar with the title and tabs stays on top.
    @State private var pinned = false
    @FocusState private var searchFocused: Bool
    @FocusState private var todoSearchFocused: Bool
    /// The bilingual column beside the notes is opt-in: three full columns of text read as crowded.
    @AppStorage("mainShowQuotes") private var showQuotes = false
    /// 左页列哪段时间的会议（分隔页「本周 / 当月 / 更早」），以及看的是哪一天。
    @State private var range: PlannerCalendar.Range = .week
    @State private var focusDate = Date()
    /// 待办页左页的搜索。
    @State private var todoQuery = ""
    /// 文字记录只看某个声音（说话人胶带点一下）。
    @State private var speakerFilter: Int?
    /// 更早页的文件夹：手动展开的、手动收起的（最新的默认开着）、列全的。
    @State private var openFolders: Set<String> = []
    @State private var closedFolders: Set<String> = []
    @State private var allFolders: Set<String> = []
    /// 分享…: the meeting whose share sheet is open.
    @State private var sharing: Session?
    /// 改这句…: the line being rewritten, and what the editor opens with.
    @State private var editingLine: String?
    @State private var editingStart = ""
    @State private var hoveredLine: String?
    @State private var wordClick = WordClick()
    @State private var keys = PlannerKeys()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wide enough for the notes and the bilingual transcript side by side.
    private var sideBySide: Bool { showQuotes && wideEnough }
    /// 手帐右页默认约 800pt 宽（窗口 1280）：「原话」并排栏到这个宽度就能开。
    private var wideEnough: Bool { detailWidth >= 760 }

    private var filtered: [Session] {
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { s in
            let terms = TranscriptSearch.terms(query, notes: s.notes?.terms ?? [])
            return s.displayTitle.localizedCaseInsensitiveContains(query) || s.lines.contains { TranscriptSearch.matches($0, terms) }
        }
    }

    /// The search in the shown record: its terms (misheard names too), the lines found, the one being looked at.
    private var searchTerms: [String] { TranscriptSearch.terms(query, notes: current?.notes?.terms ?? []) }
    private var matches: [String] { TranscriptSearch.matches(current?.lines ?? [], searchTerms) }
    private var currentMatch: String? {
        let ms = matches
        return ms.isEmpty ? nil : ms[min(matchIndex, ms.count - 1)]
    }

    private func step(_ d: Int) {
        let n = matches.count
        guard n > 0 else { return }
        matchIndex = (min(matchIndex, n - 1) + d + n) % n
    }

    /// A search that finds lines in the shown record opens its transcript at the first one.
    private func showMatches() {
        matchIndex = 0
        if !matches.isEmpty, let s = current, importer.status(of: s) == nil { tab = "transcript" }
    }

    private var current: Session? { store.session(selection ?? store.sessions.first?.id) }

    /// The shown record's audio: an imported file, or the meeting's own recording once it has ended.
    private func loadPlayer() {
        guard let s = current, s.id != store.liveID else { player.load(nil); return }
        player.load(s, recording: s.hasAudio ? store.systemAudioURL(s.id) : nil)
    }

    var body: some View {
        // 焦糖皮面手帐摊开：左页「这一周」，右页横线纸笔记，右边伸出分隔页，笔插里一支笔
        // （DESIGN.md › 主窗口（第二轮 · 手帐））。没有工具栏：开始听是那支笔，在听的标签和设置在皮面上沿。
        GeometryReader { g in
            let leftW = PlannerMetrics.leftWidth(window: g.size.width)
            // 很宽的窗口两页停在 1480 宽、居中；分隔页和笔跟着书走
            let spreadW = PlannerMetrics.spreadWidth(window: g.size.width)
            let spreadX = PlannerMetrics.spreadX(window: g.size.width)
            let spreadH = PlannerMetrics.spreadHeight(window: g.size.height)
            ZStack(alignment: .topLeading) {
                LeatherCover(emboss: true)
                // 分隔页画在纸下面，左边一截压进纸里
                DividerTabs(items: dividerItems, selected: model.todoBoardShown ? "todo" : range.rawValue) { pickDivider($0) }
                    .padding(.leading, spreadX + spreadW - DividerTabs.tucked)
                    .padding(.top, PlannerMetrics.top + 44)
                HStack(spacing: 0) {
                    leftPage(compact: PlannerMetrics.compact(window: g.size.width)).frame(width: leftW)
                    rightPage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
                }
                .frame(width: spreadW, height: spreadH)
                .background(SpreadPaper(leftWidth: leftW))
                .coverOpening(hingeX: leftW)
                .overlay(alignment: .topLeading) {
                    pageTabs
                        .alignmentGuide(.top) { $0[.bottom] }
                        .padding(.leading, leftW + PlannerMetrics.tabsInset)
                }
                .overlay(alignment: .bottom) { SpeakerUndoToast(model: model, session: selection) }
                .padding(.leading, spreadX).padding(.top, PlannerMetrics.top)
                PenInLoop(listening: model.running, label: model.running ? L("正在听") : L("开始听 ⌘R")) {
                    if model.running { model.showLiveDisplay() } else { model.setRunning(true) }
                }
                .help(model.running ? L("显示实时纪要") : L("开始听"))
                // 笔插在书的右边（窗口不宽时就是窗边）
                .padding(.leading, spreadX + spreadW + PlannerMetrics.trailing - 46)
                .padding(.top, max(PlannerMetrics.top, g.size.height - PlannerMetrics.bottom - PenInLoop.size.height))
                topBand.frame(width: g.size.width, height: PlannerMetrics.top)
                    .onReceive(NotificationCenter.default.publisher(for: .printShownMeeting)) { _ in current.map { PlannerPrint.print($0, in: PlannerPrint.mainWindow) } }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .decor(.full)
        .background(Button("") { if model.todoBoardShown { todoSearchFocused = true } else { searchFocused = true } }.keyboardShortcut("f").opacity(0))
        // Recordings and videos dropped anywhere on the window become records.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(FileImporter.importable)
            guard !files.isEmpty else { return false }
            model.importFiles(files)
            return true
        } isTargeted: { dropping = $0 }
        .overlay { if dropping { ImportDropOverlay() } }
        .onChange(of: current?.id, initial: true) { _, _ in loadPlayer() }
        .onChange(of: query) { _, _ in showMatches() }
        .onChange(of: selection) { _, _ in if !query.isEmpty { showMatches() } }
        // A meeting that ends while it is shown, and its recording once it is rewrapped into an .m4a.
        .onChange(of: store.liveID) { _, _ in loadPlayer() }
        // Opened afresh: a file opened before the room was mixed in (#19) would play one side only.
        .onChange(of: store.audioFinished) { _, id in if id == current?.id { player.unload(); loadPlayer() } }
        // A click on a line's words: its selectable text takes the mouse before the row's tap.
        .onAppear {
            wordClick.install(line: { hoveredLine.flatMap { id in editingLine == id ? nil : id } }) { id in
                guard let s = current, player.sessionID == s.id, player.ready,
                      let l = s.lines.first(where: { $0.id == id }) else { return }
                player.play(from: l.t)
            }
        }
        .onDisappear { wordClick.remove() }
        .onReceive(NotificationCenter.default.publisher(for: .debugMainSearch)) { n in
            if let text = n.object as? String { query = text } else if let d = n.object as? Int { step(d) }
            DispatchQueue.main.async {
                debugLog("main search: \"\(query)\" \(filtered.count) meetings, shown \(current?.id ?? "-") tab=\(tab) "
                         + "matches=\(matches.count) at=\(currentMatch ?? "-")")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugPlay)) { n in
            if let t = n.object as? Double { player.play(from: t) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugPlannerRange)) { n in
            if let id = n.object as? String { pickDivider(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugShareSheet)) { n in
            sharing = (n.object as? String).flatMap { store.session($0) }
        }
        .onChange(of: model.mainShow) { _, show in
            guard let parts = show?.split(separator: ",").map(String.init), let id = parts.first else { return }
            model.todoBoardShown = false
            selection = id
            tab = parts.count > 1 ? parts[1] : "notes"
            if parts.count > 2 { view = parts[2] }
        }
    }

    static let hairline = Palette.hairline
    /// 没选中的会议卡片上的图钉颜色，按会议轮换。
    static let pinColors = [Palette.inkBlue, Palette.kraft, Palette.link, Palette.ok]
    static let listTint = Palette.paperShade

    // MARK: 纸上手记：菲比、页边栏、页脚

    /// 这场会议此刻菲比的样子：只有正在记的会议、或正在为它写纪要时，纪要引擎的状态才算数。
    private func mood(_ s: Session) -> FeebeeMood {
        let live = s.id == store.liveID
        let notes = live ? model.notes.notes : s.notes
        let mine = live || model.notes.generatingID == s.id
        return FeebeeMood.of(live: live, notesState: mine ? model.notes.state : .idle,
                             hasNotes: !(notes?.isEmpty ?? true), final: notes?.final ?? false)
    }

    /// 右页够宽时有页边贴纸栏；打开「原话」并排栏时让给它（三栏太挤）。待办板不用。
    private func stripShown(_ s: Session) -> Bool {
        !model.todoBoardShown && detailWidth >= StripMetrics.minPage && !(sideBySide && activeTab(s) == "notes")
    }

    /// 页边栏「本场」四行：发言人、结论、待办、原话。
    private func stats(_ s: Session, _ notes: MeetingNotes?) -> [(label: String, count: Int, text: String)] {
        let voices = Set(s.lines.map { $0.speaker == "me" ? "me" : "them-\($0.voice ?? 0)" }).count
        let conclusions = notes?.conclusions.count ?? 0
        let todos = notes?.todos ?? []
        // 待办：划记按做完的数，右边写「做完/总数」
        let done = todos.filter { $0.status == .done }.count
        return [(L("发言人"), voices, "\(voices)"), (L("结论"), conclusions, "\(conclusions)"),
                (L("待办"), done, "\(done)/\(todos.count)"), (L("原话"), s.lines.count, "\(s.lines.count)")]
    }

    /// 页边贴纸栏（第三轮样稿）：菲比涂鸦 → 原话签 / 本场签 → 粉色待办便利贴 → 录音 → 分享、导出印章。
    private func marginStrip(_ s: Session) -> some View {
        let live = s.id == store.liveID
        let notes = live ? model.notes.notes : s.notes
        let shown = notes.map { SpeakerLabels.named($0, SpeakerLabels.names(s)) }
        let todos = shown?.todos ?? []
        let onTranscript = activeTab(s) == "transcript"
        let canAdd = notes != nil || live
        return VStack(alignment: .leading, spacing: 0) {
            FeebeeDoodle(mood: mood(s), size: 112).padding(.top, 10).padding(.leading, 26)
            Group {
                if onTranscript {
                    StripTag(text: L("本场 \(stats(s, notes)[0].count) 人 · \(s.lines.count) 句"))
                } else if wideEnough, !s.lines.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.2)) { showQuotes.toggle() } } label: {
                        StripTag(text: showQuotes ? L("收起原话 ‹") : L("原话 ›"))
                    }
                    .buttonStyle(.plain).help(showQuotes ? L("收起原话") : L("在纪要旁显示原话"))
                }
            }
            .padding(.leading, 18).padding(.top, 12)
            if !onTranscript, !todos.isEmpty || canAdd {
                let done = todos.filter { $0.status == .done }.count
                StickyNote(color: Palette.stickyPink, tape: .pinkDots, tilt: 2.2) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("待办").font(.fee(.section)).foregroundStyle(Palette.link)
                            Spacer()
                            if !todos.isEmpty { Text("\(done)/\(todos.count)").font(.fee(.meta)).foregroundStyle(Palette.secondary) }
                        }
                        ForEach(todos) { item in
                            TodoRow(item: item, compact: true, change: { [model] c in model.changeTodo(.meeting(session: s.id, key: item.key), c) })
                                .lineLimit(2)
                        }
                        if canAdd { TodoAddLine(add: { [model] text in model.addTodo(to: s.id, text: text, owner: nil, due: nil) }, compact: true) }
                    }
                }
                .frame(width: 182)
                .pressedOn()
                // 略伸出纸边一点
                .padding(.leading, 6).offset(x: 6)
                .padding(.top, 22)
            }
            Spacer(minLength: 16)
            if player.sessionID == s.id, !live, player.ready || player.missing {
                StripPlayer(player: player).padding(.horizontal, 18).padding(.bottom, 18)
            }
            stamps(s).padding(.leading, 14).padding(.bottom, 26)
        }
        .frame(width: StripMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func footer(_ s: Session) -> some View {
        let live = s.id == store.liveID
        let notes = live ? model.notes.notes : s.notes
        let voices = stats(s, notes)[0].count
        let lines = L("\(s.lines.count) 句")
        let status: String
        var detail = [lines]
        var done = false
        switch mood(s) {
        case .writing: status = L("正在写纪要…")
        case .listening: status = L("正在听…")
        case .error: status = L("纪要暂时写不了")
        case .done:
            status = L("纪要写好了")
            done = true
            if let at = notes?.updatedAt { detail.insert(L("\(dateText(at, "HHmm")) 完成"), at: 0) }
            if voices > 1 { detail.append(L("\(voices) 位发言人")) }
        case .idle: status = (notes?.isEmpty ?? true) ? L("这场会议还没有纪要") : L("速记版纪要")
        }
        return NotebookFooter(status: status, detail: detail.joined(separator: " · "), done: done, query: $query, onSubmit: { step(1) }, statusOnly: true)
    }

    // MARK: 左页「这一周」、上沿、分隔页

    private var dividerItems: [DividerTabs.Item] {
        let mine = TodoBoard.items(sessions: store.sessions, inbox: model.todoInbox.items).filter { TodoBoard.isMine($0.item) }
        let open = TodoBoard.counts(mine, today: Date()).open
        return [DividerTabs.Item(id: "todo", title: L("待办"), color: Palette.stickyPink, badge: open > 0 ? "\(open)" : nil),
                DividerTabs.Item(id: PlannerCalendar.Range.week.rawValue, title: L("本周"), color: Palette.stickyYellow),
                DividerTabs.Item(id: PlannerCalendar.Range.month.rawValue, title: dateText(focusDate, "MMMM"), color: Palette.stickyGreen),
                DividerTabs.Item(id: PlannerCalendar.Range.earlier.rawValue, title: L("更早"), color: Palette.stickySky)]
    }

    private func pickDivider(_ id: String) {
        if id == "todo" { model.todoBoardShown = true; return }
        model.todoBoardShown = false
        range = PlannerCalendar.Range(rawValue: id) ?? .week
    }

    /// 右页上沿的索引贴：会议是「纪要 / 文字记录」，待办页是「我的 / 别人的」。
    @ViewBuilder private var pageTabs: some View {
        if model.todoBoardShown {
            let items = TodoBoard.items(sessions: store.sessions, inbox: model.todoInbox.items).filter { $0.item.status != .done }
            PageTabs(items: [.init(id: "mine", title: L("我的"), count: items.filter { TodoBoard.isMine($0.item) }.count),
                             .init(id: "others", title: L("别人的"), count: items.filter { !TodoBoard.isMine($0.item) }.count)],
                     selected: model.todoBoardTab) { model.todoBoardTab = $0 }
        } else if let s = current {
            let importing = importer.status(of: s) != nil
            PageTabs(items: [.init(id: "notes", title: L("纪要"), disabled: importing, help: importing ? L("转完后生成") : nil),
                             .init(id: "transcript", title: L("文字记录"), count: s.lines.count)],
                     selected: activeTab(s)) { tab = $0 }
        }
    }

    /// 皮面上沿：正在听 / 倒计时 / 会议已自动结束的标签，和设置齿轮。
    private var topBand: some View {
        HStack(spacing: 14) {
            Spacer()
            if model.running || model.autoEnded {
                ListenPill(model: model, store: store, slot: nil).fixedSize()
            }
            Button { model.openSettings() } label: {
                Image(systemName: "slider.horizontal.3").font(.icon(14))
                    .foregroundStyle(Palette.onLeather.opacity(0.85))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("设置").accessibilityLabel(L("设置"))
        }
        .padding(.trailing, 50)
    }

    @ViewBuilder private func leftPage(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.todoBoardShown {
                todoLeftPage
            } else {
                if !query.isEmpty {
                    // 大日期旁的小字写全不截断：太长的搜索词这里先截短
                    let shown = query.count > 12 ? String(query.prefix(11)) + "…" : query
                    PlannerBigDate(big: L("找"), lines: [L("“\(shown)”"), L("\(filtered.count) 场会议")])
                    Color.clear.frame(height: PaperMetrics.pitch)
                } else {
                    rangeHeader(compact: compact)
                }
                ScrollViewReader { proxy in
                    ScrollView { timeline.padding(.trailing, 4) }
                        .scrollIndicators(.never)
                        .scrollTargetBehavior(RuleSnapScroll())
                        // ↑ / ↓ 换到看不见的那场时，把它滚进来
                        .onChange(of: selection) { _, id in if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } } }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if query.isEmpty { pagingLine }
                if query.isEmpty, range == .week { weekTodos(compact: compact) }
                searchLine
            }
        }
        .padding(.leading, 30).padding(.trailing, 26).padding(.top, PaperMetrics.pitch)
        .onAppear { focusDate = current?.startedAt ?? Date(); keys.install() }
        .onDisappear { keys.remove() }
        // 键盘写在左页上（body 再长就类型检查超时）
        .onReceive(NotificationCenter.default.publisher(for: .plannerKey)) { n in plannerKey(n.object as? String ?? "") }
        .onChange(of: current?.id) { _, _ in
            // 右页换了会议（选中、搜索、待办来源、开始听后的新会议）：左页翻到那一周
            if let s = current { focusDate = s.startedAt }
        }
    }

    private var todayTodoCount: Int {
        let mine = TodoBoard.items(sessions: store.sessions, inbox: model.todoInbox.items).filter { TodoBoard.isMine($0.item) }
        return TodoBoard.counts(mine, today: Date()).open
    }

    @ViewBuilder private func rangeHeader(compact: Bool) -> some View {
        // 小窗左页只有 224pt：月、更早的大字旁不再放「待办」印章（待办还在右边分隔页上）
        let todo = compact ? nil : (count: todayTodoCount, open: { model.todoBoardShown = true })
        switch range {
        case .week where compact:
            // 小窗（第七轮样稿 ③）：日期小一号，和周历并成一行；月和星期看周历的提示
            HStack(alignment: .center, spacing: 6) {
                Text(dateText(focusDate, "d").filter(\.isNumber)).font(.feeHero(32)).foregroundStyle(Palette.ink)
                    .lineLimit(1).fixedSize()
                    .help(dateText(focusDate, "MMMdEEEE"))
                WeekStrip(days: PlannerCalendar.week(containing: focusDate), focus: focusDate,
                          meetingDays: PlannerCalendar.meetingDays(store.sessions), pick: { pickDay($0) }, dot: 24)
            }
            .frame(height: PaperMetrics.pitch * 2)
            Color.clear.frame(height: PaperMetrics.pitch)
        case .week:
            PlannerBigDate(big: dateText(focusDate, "d").filter(\.isNumber), lines: [dateText(focusDate, "MMMM"), dateText(focusDate, "EEEE")], todo: todo)
            WeekStrip(days: PlannerCalendar.week(containing: focusDate), focus: focusDate,
                      meetingDays: PlannerCalendar.meetingDays(store.sessions)) { pickDay($0) }
            Color.clear.frame(height: PaperMetrics.pitch)
        case .month:
            PlannerBigDate(big: dateText(focusDate, "MMMM"), lines: [dateText(focusDate, "y"), L("\(PlannerCalendar.sessions(store.sessions, in: .month, around: focusDate).count) 场会议")], todo: todo)
            MonthGrid(rows: PlannerCalendar.month(containing: focusDate), focus: focusDate,
                      counts: PlannerCalendar.meetingCounts(store.sessions)) { pickDay($0) }
            Color.clear.frame(height: PaperMetrics.pitch)
        case .earlier:
            PlannerBigDate(big: L("更早"), lines: [L("\(dateText(focusDate, "MMM"))以前"), L("\(PlannerCalendar.sessions(store.sessions, in: .earlier, around: focusDate).count) 场会议")], todo: todo)
            Color.clear.frame(height: PaperMetrics.pitch)
        }
    }

    /// 点一天：看那天；那天有会议就打开最新的一场。
    private func pickDay(_ d: Date) {
        focusDate = d
        if let s = store.sessions.first(where: { PlannerCalendar.calendar.isDate($0.startedAt, inSameDayAs: d) }) {
            selection = s.id
            model.todoBoardShown = false
        }
    }

    @ViewBuilder private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !query.isEmpty {
                if filtered.isEmpty {
                    Text(L("没有找到“\(query)”")).font(.fee(.body)).foregroundStyle(Palette.secondary).frame(height: PaperMetrics.pitch)
                }
                monthGroups(PlannerCalendar.byMonth(filtered))
            } else if range == .earlier {
                let older = PlannerCalendar.sessions(store.sessions, in: .earlier, around: focusDate)
                if older.isEmpty { emptyLine(L("再往前没有会议了")) }
                folders(PlannerCalendar.byMonth(older))
            } else if range == .month {
                // 月页：按周分组，每组前面一行红铅笔小字「第 47 周 · 3 场」（第五轮样稿 ③）
                let list = PlannerCalendar.sessions(store.sessions, in: .month, around: focusDate)
                if list.isEmpty { emptyLine(L("这个月没有会议")) }
                ForEach(PlannerCalendar.byWeek(list), id: \.week) { g in
                    Text(L("第 \(g.week) 周 · \(g.sessions.count) 场")).font(.fee(.label)).foregroundStyle(Palette.link)
                        .frame(height: PaperMetrics.pitch)
                    VStack(alignment: .leading, spacing: 0) { ForEach(g.sessions) { entry($0) } }.timelineRail()
                }
            } else {
                let list = PlannerCalendar.sessions(store.sessions, in: range, around: focusDate)
                if list.isEmpty { emptyLine(store.sessions.isEmpty ? L("还没有会议") : range == .week ? L("这周没有会议") : L("这个月没有会议")) }
                VStack(alignment: .leading, spacing: 0) { ForEach(list) { entry($0) } }.timelineRail()
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(.fee(.body)).foregroundStyle(Palette.secondary).frame(height: PaperMetrics.pitch)
            .padding(.bottom, PaperMetrics.pitch)
    }

    /// 更早页（第五轮样稿 ③）：每个月一个牛皮纸文件夹，夹舌写「2026年10月 · 6 场」；点夹舌展开 / 收起，
    /// 展开的列前三场，「还有 N 场 ›」列全。最新那个月默认展开。
    private func folders(_ groups: [(title: String, sessions: [Session])]) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.title) { i, g in
            let open = openFolders.contains(g.title) || (i == 0 && !closedFolders.contains(g.title))
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if open { openFolders.remove(g.title); closedFolders.insert(g.title) }
                        else { openFolders.insert(g.title); closedFolders.remove(g.title) }
                    }
                } label: {
                    Text(L("\(g.title) · \(g.sessions.count) 场")).font(.fee(.bodySecondary, strong: true)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).frame(height: PaperMetrics.pitch)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(Palette.kraft))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    if open {
                        let all = allFolders.contains(g.title)
                        ForEach(all ? g.sessions : Array(g.sessions.prefix(3))) { s in
                            Button { selection = s.id; model.todoBoardShown = false } label: {
                                HStack(spacing: 6) {
                                    Text(RecordList.untitled(s) ? L("未命名会议") : RecordList.listTitle(s))
                                        .font(.fee(.bodySecondary, strong: s.id == selection)).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text("· " + dateText(s.startedAt, "MMMd")).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: PaperMetrics.pitch).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { sessionMenu(s) }
                            .id(s.id)
                        }
                        if !all, g.sessions.count > 3 {
                            Button { allFolders.insert(g.title) } label: {
                                Text(L("… 还有 \(g.sessions.count - 3) 场 ›")).font(.fee(.label)).foregroundStyle(Palette.secondary)
                                    .frame(height: PaperMetrics.pitch).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                // 收着的只露一道夹子边（6pt），下面补到一格，整组还在横线上
                .frame(maxWidth: .infinity, minHeight: open ? 0 : 6, alignment: .leading)
                .background(Rectangle().fill(Palette.kraft.opacity(0.75)))
                .paperShadow()
            }
            .padding(.bottom, open ? PaperMetrics.pitch : PaperMetrics.pitch - 6)
        }
    }

    private func monthGroups(_ groups: [(title: String, sessions: [Session])]) -> some View {
        ForEach(groups, id: \.title) { g in
            HStack(spacing: 8) {
                Text(g.title).font(.fee(.section))
                WavyRule(width: 50)
            }
            .foregroundStyle(Palette.ink).frame(height: PaperMetrics.pitch)
            VStack(alignment: .leading, spacing: 0) { ForEach(g.sessions) { entry($0) } }.timelineRail()
        }
    }

    /// 时间线上一场会议的第一格：正在听 / 今天写时刻 / 本周写星期 / 更早写日期，后面是时长。
    private func entryMeta(_ s: Session) -> String {
        if s.id == store.liveID { return L("现在 · 正在听") + " · " + RecordList.length(s) }
        let cal = PlannerCalendar.calendar
        let when = cal.isDateInToday(s.startedAt) ? dateText(s.startedAt, "HHmm")
            : cal.isDate(s.startedAt, equalTo: Date(), toGranularity: .weekOfYear) ? dateText(s.startedAt, "EEEHHmm")
            : dateText(s.startedAt, "MMMdHHmm")
        return when + " · " + RecordList.length(s)
    }

    /// 头像：分出来的说话人（最多四位）+ 你。
    private func entryAvatars(_ s: Session) -> [String] {
        guard settings.speakerVoices, s.lines.count < 4000 else { return s.lines.contains { $0.speaker == "me" } ? ["you"] : [] }
        let voices = Set(SpeakerLabels.numbers(s).values).sorted().prefix(4)
        return voices.compactMap { Illustration.speaker($0, me: false) } + (s.lines.contains { $0.speaker == "me" } ? ["you"] : [])
    }

    private func entry(_ s: Session) -> some View {
        let selected = !model.todoBoardShown && s.id == (selection ?? store.sessions.first?.id)
        let live = s.id == store.liveID
        return Button {
            selection = s.id
            model.todoBoardShown = false
        } label: {
            TimelineEntry(meta: entryMeta(s), selected: selected, live: live, avatars: entryAvatars(s)) {
                HStack(spacing: 6) {
                    if s.sourceFile != nil {
                        Image(systemName: "doc").font(.icon(11)).foregroundStyle(Palette.secondary)
                    } else if s.fromRecording, s.lines.isEmpty {
                        Image(systemName: "waveform").font(.icon(11)).foregroundStyle(Palette.secondary).help(L("只有录音"))
                    } else if RecordList.heardBoth(s.lines) {
                        HStack(spacing: 2) { Image(systemName: "mic"); Image(systemName: "display") }
                            .font(.fee(.label)).foregroundStyle(Palette.secondary).help(L("电脑和会议室"))
                    } else if s.room == true {
                        Image(systemName: "mic").font(.icon(11)).foregroundStyle(Palette.secondary).help(L("会议室"))
                    }
                    Text(RecordList.untitled(s) ? L("未命名会议") : RecordList.listTitle(s))
                    Spacer(minLength: 0)
                    if let status = importer.status(of: s) { Tag(rowTag(status), live: status == .running) }
                }
            }
        }
        .help(live ? L("正在记录") : [RecordList.when(s), RecordList.length(s)].joined(separator: " · "))
        .buttonStyle(.plain)
        .contextMenu { sessionMenu(s) }
        .id(s.id)
    }

    @ViewBuilder private func sessionMenu(_ s: Session) -> some View {
        let live = s.id == store.liveID
        if let path = s.sourcePath, FileManager.default.fileExists(atPath: path) {
            Button("显示原文件") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
        if s.hasAudio, !live, !working(s) {
            Menu("重新转写") {
                ForEach(sourceLanguages, id: \.locale) { lang in
                    Button(lang.name) { importer.retry(s.id, lang: lang) }
                }
            }
        }
        if s.renamed ?? !s.title.hasPrefix("会议 "), s.notes?.title != nil {
            Button("恢复自动标题") { store.rename(s.id, to: "") }
        }
        Button("删除", role: .destructive) { model.deleteSession(s.id) }.disabled(live)
    }

    /// 左页下半截（第三轮样稿）：本周待办三条（能勾）+ 一行本周小结；右下角一个小菲比。
    @ViewBuilder private func weekTodos(compact: Bool) -> some View {
        let mine = TodoBoard.items(sessions: store.sessions, inbox: model.todoInbox.items)
            .filter { TodoBoard.isMine($0.item) && $0.item.status != .done }
        let ordered = TodoBoard.groups(mine, today: Date()).flatMap(\.1)
        let week = PlannerCalendar.sessions(store.sessions, in: .week, around: focusDate)
        let sum = PlannerCalendar.summary(week)
        if compact {
            // 小窗：整块收成一行「本周待办 N 条 ›」，点开待办板
            if !ordered.isEmpty {
                Button { model.todoBoardShown = true } label: {
                    NotebookWord { Text(L("本周待办 \(ordered.count) 条 ›")) }
                        .frame(height: PaperMetrics.pitch).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("打开待办板"))
            }
        } else {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: PaperMetrics.pitch)
            if !ordered.isEmpty {
                Button { model.todoBoardShown = true } label: {
                    HStack(spacing: 6) {
                        Text("本周待办").font(.fee(.section)).foregroundStyle(Palette.ink)
                        WavyRule(width: 50)
                        Text(L("\(ordered.count) 条")).font(.fee(.label)).foregroundStyle(Palette.tertiary)
                    }
                    .frame(height: PaperMetrics.pitch).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("打开待办板"))
                ForEach(ordered.prefix(3)) { b in
                    TodoRow(item: b.item, showOwner: false, compact: true, change: { [model] c in model.changeTodo(b.ref, c) })
                        .lineLimit(1).frame(height: PaperMetrics.pitch)
                }
                Color.clear.frame(height: PaperMetrics.pitch)
            }
            if sum.count > 0 {
            (Text(L("本周 ")) + Text("\(sum.count)").foregroundStyle(Palette.link).bold() + Text(L(" 场会 · \(sum.minutes) 分钟"))
             + Text(sum.talker.map { L(" · 说得最多：\($0)") } ?? ""))
                .font(.fee(.label)).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.85)
                .frame(height: PaperMetrics.pitch)
            }
        }
        .overlay(alignment: .topTrailing) {
            // 小菲比蹲在「本周待办」那一行的右边
            FeebeeView(mood: model.running ? .listening : .idle, size: 58).rotationEffect(.degrees(8))
                .offset(x: 4, y: 6).allowsHitTesting(false)
        }
    }
    }

    /// 所看的是不是这周（月页：这个月）：再往后不翻了。
    private var atNow: Bool {
        PlannerCalendar.calendar.isDate(focusDate, equalTo: Date(), toGranularity: range == .week ? .weekOfYear : .month)
    }

    /// 翻一周（月页翻一个月）；更早页、待办页、搜索时不翻，翻到这周为止。
    private func page(_ d: Int) {
        guard !model.todoBoardShown, query.isEmpty, range != .earlier, d < 0 || !atNow else { return }
        let unit: Calendar.Component = range == .week ? .weekOfYear : .month
        focusDate = PlannerCalendar.calendar.date(byAdding: unit, value: d, to: focusDate) ?? focusDate
    }

    /// 左页时间线上会议的先后，和屏幕上一样（↑ / ↓ 换一场）：搜索结果、本周、当月按周、更早里展开的文件夹。
    private var timelineOrder: [Session] {
        if model.todoBoardShown { return [] }
        if !query.isEmpty { return PlannerCalendar.byMonth(filtered).flatMap(\.sessions) }
        let list = PlannerCalendar.sessions(store.sessions, in: range, around: focusDate)
        switch range {
        case .week: return list
        case .month: return PlannerCalendar.byWeek(list).flatMap(\.sessions)
        case .earlier:
            return PlannerCalendar.byMonth(list).enumerated().flatMap { i, g -> [Session] in
                let open = openFolders.contains(g.title) || (i == 0 && !closedFolders.contains(g.title))
                guard open else { return [] }
                return allFolders.contains(g.title) ? g.sessions : Array(g.sessions.prefix(3))
            }
        }
    }

    /// 键盘（第七轮样稿 ③，`PlannerKeys` 和菜单「显示」发来）。
    private func plannerKey(_ key: String) {
        switch key {
        case "todo", "week", "month", "earlier": pickDivider(key)
        case "left": page(-1)
        case "right": page(1)
        case "up", "down":
            let list = timelineOrder
            guard !list.isEmpty else { return }
            let i = list.firstIndex { $0.id == current?.id }
            let next = i.map { key == "up" ? max(0, $0 - 1) : min(list.count - 1, $0 + 1) } ?? 0
            selection = list[next].id
        case "notes", "transcript":
            guard !model.todoBoardShown, let s = current, importer.status(of: s) == nil else { return }
            tab = key
        default: break
        }
        DispatchQueue.main.async {
            debugLog("planner key: \(key) range=\(model.todoBoardShown ? "todo" : range.rawValue) focus=\(dateText(focusDate, "MMMd")) "
                     + "shown=\(current?.id ?? "-") tab=\(tab)")
        }
    }

    /// 「翻到上一周 ‹ / 下一周 ›」（月历是上个月 / 下个月）。
    @ViewBuilder private var pagingLine: some View {
        if range != .earlier {
            HStack(spacing: 14) {
                Button { page(-1) } label: {
                    NotebookWord { Text(range == .week ? L("翻到上一周 ‹") : L("翻到上个月 ‹")) }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if !atNow {
                    Button { page(1) } label: {
                        NotebookWord { Text(range == .week ? L("下一周 ›") : L("下个月 ›")) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: PaperMetrics.pitch)
        }
    }

    /// 最底一行：「⌕ 翻翻看… ⌘F」，有结果时上面一行「本场 2 / 7」。
    private var searchLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !query.isEmpty, !matches.isEmpty { matchBar.frame(height: PaperMetrics.pitch) }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.icon(12)).foregroundStyle(Palette.tertiary)
                TextField(L("翻翻看…"), text: $query).textFieldStyle(.plain).focusEffectDisabled().focused($searchFocused)
                    .font(.fee(.body)).foregroundStyle(Palette.ink)
                    .onSubmit { step(1) }
                if query.isEmpty {
                    Text("⌘F").font(.fee(.label)).foregroundStyle(Palette.tertiary)
                } else {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("清除")
                }
            }
            .frame(height: PaperMetrics.pitch)
        }
        .padding(.top, PaperMetrics.pitch).padding(.bottom, PaperMetrics.pitch)
    }

    /// 待办页的左页：大字「待办」、统计、这一周七天格、菲比、搜索。
    private var todoLeftPage: some View {
        let all = TodoBoard.items(sessions: store.sessions, inbox: model.todoInbox.items)
        let mine = all.filter { TodoBoard.isMine($0.item) }
        let c = TodoBoard.counts(mine, today: Date())
        let week = PlannerCalendar.week(containing: Date())
        let mood: FeebeeMood = c.overdue > 0 ? .error : (c.open == 0 ? .done : .writing)
        return VStack(alignment: .leading, spacing: 0) {
            Text("待办").font(.feeHero(40)).foregroundStyle(Palette.ink)
                .frame(height: PaperMetrics.pitch * 3, alignment: .center)
            (Text(L("没做完 \(c.open)")).foregroundStyle(Palette.secondary)
             + Text(" · ").foregroundStyle(Palette.secondary)
             + Text(L("逾期 \(c.overdue)")).foregroundStyle(c.overdue > 0 ? Palette.error : Palette.secondary)
             + Text(" · " + L("本周到期 \(c.thisWeek)")).foregroundStyle(Palette.secondary))
                .font(.fee(.bodySecondary)).lineLimit(1).frame(height: PaperMetrics.pitch)
            Color.clear.frame(height: PaperMetrics.pitch)
            DueWeekStrip(days: week, counts: PlannerCalendar.dueCounts(mine.map(\.item), week: week), overdue: c.overdue)
            Spacer(minLength: PaperMetrics.pitch)
            VStack(spacing: 4) {
                FeebeeView(mood: mood, size: 150).rotationEffect(.degrees(-4))
                Text(c.open == 0 ? L("菲比 · 都做完了") : L("菲比 · 还有 \(c.open) 条要做"))
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: PaperMetrics.pitch)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.icon(12)).foregroundStyle(Palette.tertiary)
                TextField(L("在待办里找…"), text: $todoQuery).textFieldStyle(.plain).focusEffectDisabled().focused($todoSearchFocused)
                    .font(.fee(.body)).foregroundStyle(Palette.ink)
            }
            .frame(height: PaperMetrics.pitch)
            .padding(.bottom, PaperMetrics.pitch)
        }
    }

    /// Where the search is in the shown record: 本场 2 / 7, and a way to the previous and next line.
    private var matchBar: some View {
        let n = matches.count
        return HStack(spacing: 2) {
            Text("本场 \(min(matchIndex, n - 1) + 1) / \(n)")
                .font(.fee(.meta)).foregroundStyle(Palette.secondary)
            Spacer(minLength: 4)
            matchButton("chevron.up", help: L("上一个")) { step(-1) }
            matchButton("chevron.down", help: L("下一个")) { step(1) }
        }
    }

    private func matchButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.icon(11, weight: .semibold)).foregroundStyle(Palette.secondary)
                .frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    /// Being transcribed or waiting to be.
    private func working(_ s: Session) -> Bool {
        switch importer.status(of: s) {
        case .running, .queued: return true
        default: return false
        }
    }

    /// The list row's word for an imported file still being worked on.
    private func rowTag(_ status: FileImporter.Status) -> String {
        switch status {
        case .queued: return L("排队中")
        case .unfinished: return L("没转完")
        case .running:
            switch importer.phase {
            case .transcribing: return L("转写中 \(Int(importer.progress * 100))%")
            case .translating: return L("翻译中")
            default: return L("准备中")
            }
        }
    }

    // MARK: 右页

    /// 右页：会议笔记或待办板；右上角菲比涂鸦，右下角「分享」「导出」两个印章。横线由整张纸画，滚动停在格上。
    /// 换会议、换标签、翻到待办时右页翻一页。
    private var pageKey: String {
        model.todoBoardShown ? "todo-\(model.todoBoardTab)" : "\(current?.id ?? "-")-\(current.map(activeTab) ?? "")"
    }

    private var rightPage: some View {
        ZStack {
            detail
                .id(pageKey)
                .transition(.pageTurn)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: pageKey)
            .environment(\.spreadRules, true)
            .overlay(alignment: .bottomTrailing) {
                // 窄窗没有贴纸栏：印章缩小，落在最下面页脚那一行的右边，不压正文
                if !model.todoBoardShown, let s = current, !stripShown(s) {
                    stamps(s).scaleEffect(0.5, anchor: .bottomTrailing).padding(.trailing, 8)
                }
            }
    }

    /// 「分享」「导出」：墨水印章。规则同原来的「分享…」「导出…」：会议进行中、导入没转完、没有内容时不能用。
    private func stamps(_ s: Session) -> some View {
        HStack(spacing: 14) {
            Button { sharing = s } label: { InkStamp(text: L("分享"), color: Palette.inkBlue) }
                .buttonStyle(.plain)
                .disabled((s.lines.isEmpty && (s.notes?.isEmpty ?? true)) || store.liveID == s.id || importer.status(of: s) != nil)
                .help(L("分享…"))
                .sheet(item: $sharing) { shared in ShareSheet(session: shared) { sharing = nil } }
            Menu {
                Button("复制全文") { model.export(s, kind: "copy") }
                Divider()
                Button("导出 Markdown…") { model.export(s, kind: "md") }
                Button("导出 Word…") { model.export(s, kind: "word") }
                Button("导出 PDF…") { model.export(s, kind: "pdf") }
                Button("导出字幕 SRT…") { model.export(s, kind: "srt") }
                Divider()
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.folder(s.id)]) }
            } label: {
                InkStamp(text: L("导出"), color: Palette.link, tilt: 7)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(s.lines.isEmpty)
            .help(L("导出…"))
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if model.todoBoardShown {
            TodoBoardView(model: model, store: store, inbox: model.todoInbox, openMeeting: { id, t in
                // 来源会议名：打开那场的文字记录，跳到出处那句
                model.todoBoardShown = false
                selection = id
                tab = "transcript"
                jumpTo = t
            }, planner: true, externalQuery: $todoQuery)
        } else if let s = current {
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                if s.lines.isEmpty {
                    ScrollView {
                        header(s).notebookColumn()
                    }
                        .overlay {
                            Text(s.id == store.liveID ? L("正在听，说话的内容会出现在这里")
                                 : working(s) ? L("转出的文字会陆续出现在这里")
                                 : s.fromRecording ? L("还没有文字记录") : L("这场会议没有记录到内容"))
                                .font(.fee(.body)).foregroundStyle(Palette.secondary)
                        }
                } else if tab == "notes", importer.status(of: s) == nil {
                    HStack(spacing: 0) {
                        SessionNotesView(model: model, engine: model.notes, ling: model.ling, session: s,
                                         header: AnyView(header(s)), bar: { toTop in AnyView(pinnedBar(s, column: 600, inset: 44, toTop: toTop)) },
                                         todosInMargin: stripShown(s)) { t in
                            // Beside the notes, a topic's time scrolls the column; otherwise it opens the transcript.
                            if sideBySide { quoteJump = t } else { jumpTo = t; tab = "transcript" }
                        }
                        if sideBySide {
                            quotes(s).frame(width: 300).padding(.trailing, 24)
                        }
                    }
                } else {
                    transcript(s)
                }
                if s.id == store.liveID { liveNow }
                // Under the page, not in its header: the controls stay while the transcript scrolls.
                if player.sessionID == s.id, s.id != store.liveID, player.ready || player.missing, !stripShown(s) {
                    RecordingPlayerBar(player: player)
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 40).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.paper)
                        .overlay(alignment: .top) { Rectangle().fill(Self.hairline).frame(height: 1) }
                }
                footer(s).padding(.leading, PaperMetrics.marginX)
            }
            if stripShown(s) { marginStrip(s) }
            }
            .onChange(of: s.id) { _, _ in pinned = false; speakerFilter = nil }
            .onChange(of: tab) { _, _ in pinned = false }
        } else {
            welcome
        }
    }

    /// 还没有会议（第四轮样稿 ①）：菲比在纸上打盹，手写一句，下面三条「从这儿开始」，一道红铅笔虚线箭头指向右边那支笔。
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeebeeView(mood: .idle, size: 120).rotationEffect(.degrees(-5)).padding(.leading, 40)
                .frame(height: PaperMetrics.pitch * 6, alignment: .bottom)
            Text(CJKPunct.tightened(L("这本手帐还是空的"), size: 26)).font(.fee(.display)).frame(height: PaperMetrics.pitch * 2, alignment: .bottom)
            Color.clear.frame(height: PaperMetrics.pitch)
            HStack(spacing: 4) {
                Button { model.ensureListening(); model.sample.play() } label: { NotebookWord { Text("先听一段示例") } }
                    .buttonStyle(.plain)
                Text("· 看看纪要怎么写出来").foregroundStyle(Palette.secondary)
            }
            .frame(height: PaperMetrics.pitch)
            HStack(spacing: 4) {
                Button { model.chooseImportFiles() } label: { NotebookWord { Text(CJKPunct.tightened(L("导入录音、视频…"))) } }
                    .buttonStyle(.plain)
                Text("· 也可以直接拖进窗口").foregroundStyle(Palette.secondary)
            }
            .frame(height: PaperMetrics.pitch)
            HStack(spacing: 4) {
                Text("或者点右边那支笔").foregroundStyle(Palette.secondary)
                Button { model.setRunning(true) } label: {
                    Text("开始听 ⌘R").font(.fee(.body, strong: true)).foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            .frame(height: PaperMetrics.pitch)
        }
        .font(.fee(.body))
        .padding(.leading, PaperMetrics.marginX + NotebookMetrics.gutter).padding(.top, PaperMetrics.pitch)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            // 指向笔插的红铅笔虚线箭头
            Canvas { c, size in
                var p = Path()
                p.move(to: CGPoint(x: 4, y: size.height * 0.2))
                p.addCurve(to: CGPoint(x: size.width - 6, y: size.height - 8),
                           control1: CGPoint(x: size.width * 0.4, y: size.height * 0.1),
                           control2: CGPoint(x: size.width * 0.8, y: size.height * 0.4))
                c.stroke(p, with: .color(Palette.link), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5, 4]))
                var head = Path()
                head.move(to: CGPoint(x: size.width - 18, y: size.height - 10))
                head.addLine(to: CGPoint(x: size.width - 6, y: size.height - 8))
                head.addLine(to: CGPoint(x: size.width - 10, y: size.height - 20))
                c.stroke(head, with: .color(Palette.link), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            .frame(width: 150, height: 110)
            .padding(.trailing, 8).padding(.bottom, 60)
            .allowsHitTesting(false)
        }
    }

    /// 此刻: the sentence being heard, pinned under the page while the meeting is live.
    @ViewBuilder private var liveNow: some View {
        let src = model.liveSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty || !model.languageAsk.isEmpty || model.modelFetch != nil || model.cloud.listening || model.cloud.back != nil {
            // 「此刻」是一张贴在页底的黄便签（第三轮样稿 › 正在听）
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    BreathingDot(size: 6)
                    Text("此刻").font(.fee(.label, strong: true)).foregroundStyle(Palette.accentInk)
                }
                .frame(height: PaperMetrics.pitch)
                Text(src).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .lineLimit(2).truncationMode(.head)
                // 听不出 replaces the stuck 正在识别语言…; it says what to do instead.
                if !model.liveTranslation.isEmpty, model.languageAsk.isEmpty {
                    Text(model.liveTranslation).font(.fee(.body)).foregroundStyle(Palette.ink)
                        .lineLimit(2).truncationMode(.head)
                }
                LanguageNotice(model: model).padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Palette.stickyYellow))
            .overlay(alignment: .top) { Tape(style: .greenCheck, width: 70).offset(y: -8) }
            .paperShadow(deeper: true)
            .tilted(-0.6)
            .padding(.leading, PaperMetrics.marginX + 12).padding(.trailing, 28).padding(.vertical, 8)
            .pressedOn()
        }
    }

    /// 页眉的工具行有东西才画（第三轮：不留空行）。
    private func toolsVisible(_ s: Session) -> Bool {
        activeTab(s) == "transcript" || (wideEnough && !s.lines.isEmpty && !stripShown(s))
            || (s.hasAudio && store.liveID != s.id && importer.status(of: s) == nil)
    }

    /// Text tabs, the transcript's language choice and 导出…, under the title: no toolbar band.
    private func tabsRow(_ s: Session) -> some View {
        HStack(alignment: .center, spacing: 22) {
            tools(s)
            Spacer()
        }
        .frame(height: PaperMetrics.pitch)
    }

    /// Notes wait until an imported file is transcribed to the end.
    private func activeTab(_ s: Session) -> String { importer.status(of: s) != nil ? "transcript" : tab }

    /// The transcript's language choice (or 原话 beside the notes) and 导出….
    private func tools(_ s: Session) -> some View {
        let active = activeTab(s)
        return HStack(alignment: .center, spacing: 22) {
            if active == "transcript" {
                // 双语 / 原文 / 译文：当前那个是带虚线的字，另外两个淡一点
                HStack(spacing: 14) {
                    ForEach([("both", L("双语")), ("src", L("原文")), ("dst", L("译文"))], id: \.0) { id, title in
                        Button { view = id } label: { NotebookWord(on: view == id) { Text(title) }.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                    }
                }
            } else if wideEnough, !s.lines.isEmpty, !stripShown(s) {
                Button { withAnimation(.easeOut(duration: 0.2)) { showQuotes.toggle() } } label: {
                    NotebookWord(on: true) { Text("原话").foregroundStyle(showQuotes ? Palette.ink : Palette.secondary) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showQuotes ? L("收起原话") : L("在纪要旁显示原话"))
            }
            if s.hasAudio, store.liveID != s.id, importer.status(of: s) == nil {
                Menu {
                    ForEach(sourceLanguages, id: \.locale) { lang in
                        Button(lang.name) { importer.retry(s.id, lang: lang) }
                    }
                } label: {
                    NotebookWord { Text("重新转写") }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(L("用保存的录音重新识别，替换现在的文字记录和纪要；旧记录会先备份"))
            }
        }
    }

    /// Once the title block scrolls away: the title (a click goes back to the top) and the tabs row,
    /// so switching tabs, the transcript's language or exporting never needs a scroll back up.
    private func pinnedBar(_ s: Session, column: CGFloat = 680, inset: CGFloat = 40, toTop: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Button(action: toTop) {
                HStack(spacing: 6) {
                    if s.id == store.liveID { BreathingDot(size: 6) }
                    Text(RecordList.untitled(s) ? L("未命名会议") : RecordList.listTitle(s))
                        .font(.fee(.body, strong: true)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(L("回到顶部"))
            // The title takes what the tabs and tools leave, so the bar keeps to the text column.
            .frame(maxWidth: .infinity, alignment: .leading)
            tools(s)
        }
        .frame(maxWidth: column)
        .padding(.horizontal, inset).frame(height: PaperMetrics.pitch * 2)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Self.hairline).frame(height: 1) }
        .transition(.opacity)
    }

    /// One grey line of facts, the editable title, then the tabs: the top of the page, scrolling with it.
    private func header(_ s: Session) -> some View {
        let live = s.id == store.liveID
        let notes = live ? model.notes.notes : s.notes
        // When and how long up front; the languages and notes version wait in the tooltip.
        let more = [RecordList.pair(s, short: false),
                    notes.flatMap { $0.isEmpty ? nil : ($0.final ? L("完整版纪要") : L("速记版纪要")) }]
        // 角色栏里是菲比（当前状态），右边标题占两格、元信息一格（样稿 › 页眉）
        return VStack(alignment: .leading, spacing: 0) {
            GutterRow(gutter: { Color.clear.frame(height: 72) }) {
                VStack(alignment: .leading, spacing: 0) {
                    RecordTitleField(session: s, store: store).id(s.id).frame(minHeight: 48, alignment: .center)
                        // 长标题换成两行时，高度取 24 的整数倍，下面的元信息还落在横线上
                        .snapToRules()
                    HStack(spacing: 8) {
                        if live { Tag(L("正在记录"), live: true) }
                        Text(([dateText(s.startedAt, "MMMdEEEHHmm"), RecordList.length(s)] + (s.sourceFile.map { [$0, L("导入")] } ?? [])
                              + (RecordList.heardBoth(s.lines) ? [L("电脑和会议室")] : s.room == true ? [L("会议室")] : [])
                              + more.compactMap { $0 }).joined(separator: " · "))
                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary).lineLimit(1)
                            .help(([dateLine(s, live: live)] + more.compactMap { $0 }).joined(separator: " · "))
                    }
                    .frame(height: PaperMetrics.pitch)
                }
                // 没有贴纸栏时右上角留给菲比涂鸦
                .padding(.trailing, stripShown(s) ? 0 : 96)
            }
            GutterRow {
            VStack(alignment: .leading, spacing: 0) {
            if !live { FolderExportLine(exporter: model.folderExport, model: model, session: s) }
            if s.sourcePath != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if s.fromRecording, s.lines.isEmpty || s.importing == true, !working(s) {
                        RecordingLanguageStrip(importer: importer, session: s)
                    } else {
                        ImportStatusStrip(model: model, importer: importer, session: s)
                    }
                }
                .padding(.top, 16)
            } else if live {
                if settings.recordAudio {
                    Text("会议结束后可以回放录音").font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary).padding(.top, 10)
                }
            } else if !s.hasAudio, !s.lines.isEmpty {
                HStack(spacing: 4) {
                    Text("这场会议没存录音 ·").foregroundStyle(Palette.tertiary)
                    Button(L("保存会议录音")) { model.openSettings(.records) }
                        .buttonStyle(.plain).foregroundStyle(Palette.link)
                }
                .font(.fee(.bodySecondary)).padding(.top, 10)
            }
            }
            }
            if toolsVisible(s) { GutterRow { tabsRow(s) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 页边的菲比涂鸦：贴在页眉右上角，跟着页面一起滚走
        .overlay(alignment: .topTrailing) { if !stripShown(s) { FeebeeDoodle(mood: mood(s)).offset(x: 6, y: -14) } }
    }

    /// The bilingual lines beside the notes, so the record's two languages show without switching tabs.
    private func quotes(_ s: Session) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("原话").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(L("全部 \(s.lines.count) 句")) { tab = "transcript" }
                            .buttonStyle(.plain).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    }
                    .padding(.bottom, 8)
                    let speakers = settings.speakerVoices ? SpeakerLabels.numbers(s) : [:]
                    let starts = SpeakerLabels.runStarts(s.lines, speakers)
                    ForEach(s.lines) { l in
                        quoteRow(l, speaker: speakers[l.id], picked: quoteJump.map { t in l.id == pickedLine(s, t)?.id } ?? false,
                                 label: settings.speakerEveryLine || starts.contains(l.id), voices: !speakers.isEmpty).id(l.id)
                    }
                }
                .environment(\.speakerNames, SpeakerLabels.names(s))
                .padding(.vertical, 40)
            }
            .scrollIndicators(.never)
            .onChange(of: quoteJump) { _, t in
                guard let t, let l = pickedLine(s, t) else { return }
                withAnimation { proxy.scrollTo(l.id, anchor: .top) }
            }
            .onChange(of: s.lines.count) { _, _ in
                if s.id == store.liveID, quoteJump == nil, let last = s.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: s.id) { _, _ in quoteJump = nil }
        }
    }

    private func pickedLine(_ s: Session, _ t: Double) -> TranscriptLine? {
        s.lines.first(where: { $0.t >= t - 1 }) ?? s.lines.last
    }

    /// Whitespace between lines, no rules; the picked line gets a soft fill.
    private func quoteRow(_ l: TranscriptLine, speaker: Int?, picked: Bool, label: Bool = true, voices: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Only once voices are told apart (or for your own lines): one speaker needs no label;
            // and only where the speaker changes.
            if !label {
            } else if let speaker { SpeakerTag(number: speaker).padding(.bottom, 2) }
            else if voices, l.speaker != "me" { UnknownSpeakerTag().padding(.bottom, 2) }
            else if l.speaker == "me" { MeTag().padding(.bottom, 2) }
            Text(l.shown).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).lineSpacing(1)
                .textSelection(.enabled)
            Text(l.dst ?? L("翻译中…")).font(.fee(.body)).lineSpacing(2)
                .foregroundStyle(l.dst == nil ? Palette.secondary : Palette.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(Rectangle().fill(picked ? Palette.mark.opacity(0.5) : .clear))
        .padding(.horizontal, -8)
        .help(TranscriptExport.clock(l.t))
    }

    private func dateLine(_ s: Session, live: Bool) -> String {
        let start = dateText(s.startedAt, "MMMdEEEHHmm")
        guard !live, let end = s.endedAt else { return live ? L("\(start) 起") : start }
        return "\(start) – \(dateText(end, "HHmm"))"
    }

    private func transcript(_ s: Session) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The header outside the lazy stack, so it is never dropped and always reports where it is.
                VStack(alignment: .leading, spacing: 0) {
                header(s).padding(.bottom, PaperMetrics.pitch)
                    .id(PinnedHeader.top)
                    .pinnedHeader($pinned)
                LazyVStack(alignment: .leading, spacing: 0) {
                    let speakers = settings.speakerVoices ? SpeakerLabels.numbers(s) : [:]
                    if !speakers.isEmpty || (settings.speakerVoices && SpeakerLabels.singleVoice(s.lines) != nil) { SpeakerStrip(model: model, session: s, filter: $speakerFilter).padding(.bottom, 8) }
                    let both = RecordList.heardBoth(s.lines)
                    // In a meeting that heard the room and the Mac, a change of place starts a new run too.
                    let starts = SpeakerLabels.runStarts(s.lines, speakers).union(both ? RecordList.placeStarts(s.lines) : [])
                    let voices = SpeakerLabels.voiceNumbers(s)
                    let playingLine = player.lineID(in: s)
                    let terms = searchTerms
                    let found = currentMatch
                    if s.id != store.liveID {
                        FixReviewBanner(fixes: model.fixes, session: s, onShow: { id in withAnimation { onRules(proxy, s, id) } },
                                        onEdit: { l, suggestion in editingStart = suggestion; editingLine = l.id; onRules(proxy, s, l.id) })
                            .padding(.bottom, 10)
                    }
                    ForEach(speakerFilter.map { v in s.lines.filter { $0.voice == v } } ?? s.lines) { l in
                        lineRow(l, speaker: speakers[l.id], label: speakers.isEmpty || settings.speakerEveryLine || starts.contains(l.id), voices: !speakers.isEmpty, place: both, in: s,
                                current: l.id == playingLine, terms: terms, found: l.id == found)
                            .contextMenu {
                                Button(L("改这句…")) { editingStart = l.shown; editingLine = l.id }
                                if !speakers.isEmpty, l.speaker == "them" { assignMenu(s, l, voices) }
                            }
                            .id(l.id)
                    }
                }
                }
                .environment(\.speakerNames, SpeakerLabels.names(s))
                .notebookColumn()
            }
            .scrollTargetBehavior(RuleSnapScroll())
            .coordinateSpace(name: PinnedHeader.space)
            .overlay(alignment: .top) {
                if pinned { pinnedBar(s) { withAnimation { proxy.scrollTo(PinnedHeader.top, anchor: .top) } } }
            }
            .animation(.easeOut(duration: 0.15), value: pinned)
            .onUserScroll(ownSince: { player.ownScroll }) { if player.sessionID == s.id { player.userScrolled() } }
            .overlay(alignment: .bottom) { FixToast(fixes: model.fixes).padding(.bottom, 18) }
            .overlay(alignment: .bottom) {
                // Scrolled away from what is playing: one way back.
                if player.sessionID == s.id, !player.following, let id = player.lineID(in: s),
                   let l = s.lines.first(where: { $0.id == id }) {
                    Button { player.follow() } label: {
                        // 挂在纸边的黄吊牌（第四轮样稿 ⑥）
                        KraftLabel(color: Palette.stickyYellow) {
                            Text("▸ " + L("回到正在播放") + " · " + TranscriptExport.clock(l.t)).font(.fee(.body, strong: true))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).linkPointer()
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: player.following)
            .onChange(of: s.lines.count) { _, _ in
                if s.id == store.liveID, let last = s.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            // The transcript follows the recording while it plays, until scrolled by hand.
            .onChange(of: player.lineID(in: s)) { _, id in
                if player.playing, player.following, let id {
                    player.ownScroll = Date()
                    withAnimation { onRules(proxy, s, id) }
                }
            }
            .onChange(of: player.following) { _, on in
                if on, let id = player.lineID(in: s) {
                    player.ownScroll = Date()
                    withAnimation { onRules(proxy, s, id) }
                }
            }
            .onChange(of: currentMatch) { _, id in
                if let id { withAnimation { onRules(proxy, s, id) } }
            }
            .onAppear {
                if let t = jumpTo, let l = s.lines.first(where: { $0.t >= t - 1 }) { onRules(proxy, s, l.id) }
                else if let id = currentMatch {
                    // Opened by a search: the lazy list needs a moment to lay out before it can go to the line found.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onRules(proxy, s, id) }
                }
                jumpTo = nil
            }
        }
    }

    /// 跳到一句（搜索、播放跟随、跳到出处）：把它前一句顶到可见区上沿。每句的上沿都在 24pt 格上，
    /// 所以停下来字还落在横线上；要找的那句露在固定条下面，不会被挡住。
    private func onRules(_ proxy: ScrollViewProxy, _ s: Session, _ id: String) {
        let shown = speakerFilter.map { v in s.lines.filter { $0.voice == v } } ?? s.lines
        guard let i = shown.firstIndex(where: { $0.id == id }) else { return }
        proxy.scrollTo(i > 0 ? shown[i - 1].id : PinnedHeader.top, anchor: .top)
    }

    private func lineRow(_ l: TranscriptLine, speaker: Int? = nil, label: Bool = true, voices: Bool = false, place: Bool = false, in shownSession: Session? = nil, current: Bool = false,
                         terms: [String] = [], found: Bool = false) -> some View {
        let me = l.speaker == "me"
        let playable = shownSession.map { player.sessionID == $0.id && player.ready } ?? false
        let hovered = playable && hoveredLine == l.id && editingLine != l.id
        // 样稿 › 文字记录：角色栏放说话人头像（一段话的第一句才画），第一行名字 + 时间，下面原文、译文各占一格
        let names = shownSession.map(SpeakerLabels.names) ?? [:]
        let avatar: (String, Color)? = !label ? nil
            : me ? (L("你"), Palette.you)
            : speaker.map { (names[$0] ?? "\($0)", SpeakerColor.ink($0)) } ?? (L("对方"), Palette.secondary)
        let picture = Illustration.speaker(speaker, me: me)
        let textColor: Color? = me ? Palette.you : nil
        return HStack(alignment: .top, spacing: 0) {
            Group {
                if let avatar { SpeakerAvatar(text: avatar.0, color: avatar.1, image: picture) } else { Color.clear }
            }
            .frame(width: NotebookMetrics.gutter, height: PaperMetrics.pitch, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if !label {
                    } else if voices, !me, let s = shownSession {
                        // A click on whose line it is: say it was someone else's, or name the voice.
                        Menu {
                            if let v = l.voice {
                                Button(L("标记人名…")) { model.promptSpeakerName(session: s.id, voice: v) }
                                if model.settings.speakerMemory, s.id != model.store.liveID {
                                    Button(L("记住这个声音…")) { model.rememberSpeaker(session: s.id, voice: v) }
                                }
                                Divider()
                            }
                            assignMenu(s, l, SpeakerLabels.voiceNumbers(s))
                        } label: {
                            if let speaker { SpeakerTag(number: speaker) } else { UnknownSpeakerTag() }
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                        .help(L("这句是谁说的"))
                    } else if let speaker { SpeakerTag(number: speaker) }
                    else if let s = shownSession, let v = l.voice {
                        // A one-to-one call (or a voice not on show yet): make 对方 clickable to name.
                        Menu {
                            Button(L("标记人名…")) { model.promptSpeakerName(session: s.id, voice: v) }
                            if model.settings.speakerMemory, s.id != model.store.liveID {
                                Button(L("记住这个声音…")) { model.rememberSpeaker(session: s.id, voice: v) }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("对方").font(.fee(.label, strong: true)).foregroundStyle(Palette.secondary)
                                Image(systemName: "chevron.down").font(.icon(7, weight: .bold)).foregroundStyle(Palette.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(L("标记这个人叫什么"))
                    }
                    else if shownSession?.sourceFile == nil {
                        // An imported file has no "other side": its lines carry no label.
                        if me { MeTag() } else {
                            Text("对方").font(.fee(.label, strong: true)).foregroundStyle(Palette.secondary)
                        }
                    }
                    if place, label, !me { PlaceTag(line: l) }
                }
                // 一段话的第一句才有名字那一格；时间写在红线左边的页边（第三轮样稿 › 文字记录）
                .frame(height: label ? PaperMetrics.pitch : 0)
                .clipped()
                if editingLine == l.id, let s = shownSession {
                    LineEditor(line: l, session: s.id, fixes: model.fixes, start: editingStart) { editingLine = nil }
                } else if view != "dst" {
                    Text(CJKPunct.tightened(TranscriptSearch.highlighted(TranscriptParagraphs.joinFixed([l]), terms, current: found)))
                        .ruledText(view == "src" ? .body : .bodySecondary)
                        .foregroundStyle(textColor ?? (view == "src" ? Palette.ink : Palette.secondary))
                        .textSelection(.enabled)
                }
                if view != "src" {
                    Text(l.dst.map { CJKPunct.tightened(TranscriptSearch.highlighted(AttributedString($0), terms, current: found)) } ?? AttributedString(L("翻译中…")))
                        .ruledText(.body)
                        .foregroundStyle(l.dst == nil ? Palette.tertiary : textColor ?? Palette.ink)
                        // 正在放的那句划荧光笔
                        .background(current ? Palette.mark.opacity(0.75) : .clear)
                        .textSelection(.enabled)
                }
                // Pointing at a line: what its fixed words were heard as, 改回, and 改这句….
                if hoveredLine == l.id, editingLine != l.id, let s = shownSession {
                    HStack(spacing: 8) {
                        let fixed = (l.fixes ?? []).filter(\.applied).map { (l.id, $0) }
                        if !fixed.isEmpty { FixedWords(fixes: fixed) { id, f in model.fixes.revert(f, lineID: id, in: s.id) } }
                        Button(L("改这句…")) { editingStart = l.shown; editingLine = l.id }
                            .buttonStyle(.plain).font(.fee(.label, strong: true)).foregroundStyle(Palette.link)
                    }
                    .padding(.top, 2)
                }
            }
            // 你说的话整段往右缩一截
            .padding(.leading, me ? 40 : 0)
            Spacer(minLength: 0)
            PlayingBars(on: current && player.playing).frame(width: 14).padding(.top, 4)
        }
        .overlay(alignment: .topLeading) {
            Group {
                if playable {
                    // The recording plays from this line (so does a click anywhere on it).
                    Button { player.play(from: l.t) } label: {
                        Text((current ? "▸ " : hovered ? "▶ " : "") + TranscriptExport.clock(l.t))
                            .font(.fee(.meta, strong: current || hovered))
                            .foregroundStyle(current || hovered ? Palette.accent : Palette.link)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(L("从这里播放"))
                } else {
                    Text(TranscriptExport.clock(l.t)).font(.fee(.meta)).foregroundStyle(Palette.link.opacity(0.8))
                }
            }
            .fixedSize()
            .frame(width: PaperMetrics.marginX - 10, height: PaperMetrics.pitch, alignment: .trailing)
            .offset(x: -PaperMetrics.marginX)
        }
        .contentShape(Rectangle())
        .onHover { inside in if inside { hoveredLine = l.id } else if hoveredLine == l.id { hoveredLine = nil } }
        // A click anywhere on the line plays from it; a drag selects text instead (a tap ends without moving).
        .onTapGesture { if playable, editingLine != l.id { player.play(from: l.t) } }
        // The line the recording is playing; a lighter fill under the pointer when a click would play it.
        .background(Rectangle().fill(hovered ? Palette.paperShade.opacity(0.7) : .clear)
            .padding(.leading, NotebookMetrics.gutter - 6))
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

extension MainWindowView {
    /// "这句是谁说的": the people on show; the line takes that voice.
    @ViewBuilder
    func assignMenu(_ s: Session, _ l: TranscriptLine, _ voices: [Int: Int]) -> some View {
        let names = SpeakerLabels.names(s)
        Section("这句是谁说的") {
            ForEach(voices.sorted { $0.value < $1.value }, id: \.key) { v, n in
                Button(SpeakerLabels.label(n, names) + (l.voice == v ? " ✓" : "")) {
                    model.assignLines(session: s.id, [l.id], to: v)
                }
            }
        }
    }
}

/// A meeting's notes in the main window: the same notes view as the live window, or a way to
/// make them for a meeting recorded without a key.
struct SessionNotesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: NotesEngine
    @ObservedObject var ling: LingClient
    let session: Session
    /// The page's title block, scrolling with the notes.
    var header: AnyView = AnyView(EmptyView())
    /// The slim bar shown on top once the header scrolls away, given a way back to the top.
    var bar: ((@escaping () -> Void) -> AnyView)? = nil
    /// 待办画在页边栏的便利贴上（宽窗）。
    var todosInMargin = false
    let onJump: (Double) -> Void
    @State private var pinned = false

    private var live: Bool { session.id == model.store.liveID }
    private var notes: MeetingNotes? { live ? engine.notes : session.notes }
    private var generating: Bool { engine.generatingID == session.id }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
                header.id(PinnedHeader.top).pinnedHeader($pinned)
                if let notes, !notes.isEmpty {
                    NotesContentView(notes: SpeakerLabels.named(notes, SpeakerLabels.names(session)), fresh: live ? engine.fresh : [], live: live, document: true,
                                     endedAt: session.lines.last?.t, onJump: onJump, editing: model.editHooks(session),
                                     todosInMargin: todosInMargin,
                                     todoChange: { [model, session] item, change in model.changeTodo(.meeting(session: session.id, key: item.key), change) },
                                     todoAdd: { [model, session] text in model.addTodo(to: session.id, text: text, owner: nil, due: nil) })
                } else if generating || (live && ling.hasKey && !session.lines.isEmpty && engine.state == .updating) {
                    NotebookPendingNotes(writing: true, heard: session.lines.count)
                } else if live && ling.hasKey {
                    NotebookPendingNotes(writing: false, heard: session.lines.count)
                } else {
                    // 空状态（第四轮样稿 ①）：一句话 + 印章「写纪要」；没接 Ling 时旁边一张黄便签说去哪里填
                    VStack(alignment: .leading, spacing: 0) {
                        Text(generating ? L("正在整理纪要…") : live ? L("纪要会在会议进行中自动生成") : L("这场会议还没有纪要"))
                            .font(.fee(.title)).frame(height: PaperMetrics.pitch * 2, alignment: .leading)
                        Text(ling.hasKey ? L("用 \(ling.provider.name) 整理出总结、议题、结论和人名，约半分钟。")
                                         : L("前往 设置 › AI 服务 填入 Ling 的 API key 后即可生成。"))
                            .ruledText(.bodySecondary).foregroundStyle(Palette.secondary)
                        if !live {
                            HStack(alignment: .top, spacing: 28) {
                                if ling.hasKey {
                                    Button { engine.generate(for: session.id) } label: {
                                        InkStamp(text: generating ? L("在写…") : L("写纪要"), color: Palette.accentInk)
                                    }
                                    .buttonStyle(.plain).disabled(generating)
                                    .help(L("生成纪要"))
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("还没接 Ling？").font(.fee(.body, strong: true)).foregroundStyle(Palette.inkBlue)
                                        Text("设置 › AI 服务，贴上 sk- 开头的 key 就行。").font(.fee(.label)).foregroundStyle(Palette.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        SoftButton(L("去填 key")) { model.openSettings(.ai) }.padding(.top, 2)
                                    }
                                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                                    .frame(width: 240, alignment: .leading)
                                    .slipBackground(.note)
                                    .tilted(2)
                                }
                                FeebeeView(mood: .idle, size: 72).rotationEffect(.degrees(-6)).padding(.top, 20)
                            }
                            .padding(.top, PaperMetrics.pitch)
                        }
                    }
                    .padding(.leading, NotebookMetrics.gutter).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .notebookColumn()
        }
        .scrollTargetBehavior(RuleSnapScroll())
        .coordinateSpace(name: PinnedHeader.space)
        .overlay(alignment: .top) {
            if pinned, let bar { bar { withAnimation { proxy.scrollTo(PinnedHeader.top, anchor: .top) } } }
        }
        .animation(.easeOut(duration: 0.15), value: pinned)
        .onChange(of: session.id) { _, _ in pinned = false }
        }
    }
}

/// A page's title block scrolling out of its scroll view, which names its coordinate space `space`.
enum PinnedHeader {
    static let space = "cicada.page"
    static let top = "cicada.page.top"
}

extension View {
    /// Sets `pinned` while this view's bottom is above the scroll view's top edge.
    func pinnedHeader(_ pinned: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { $0.frame(in: .named(PinnedHeader.space)).maxY < 0 } action: { pinned.wrappedValue = $0 }
    }
}

/// Under 此刻 while "auto" can't tell the language yet: the second speech model coming in, or,
/// when nothing more will settle it, 听不出 with the likely languages to pick from.
struct LanguageNotice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let service = model.cloud.back {
            cloudBackCard(service)
        } else if model.cloud.listening, !Recognition.cloudOnly, let service = model.cloud.service {
            cloudCard(service)
        } else if let problem = model.modelProblem, !model.languageAsk.isEmpty || model.modelBlocked {
            problemCard(problem)
        } else if model.languageNotInstalled {
            notInstalledCard
        } else if !model.languageAsk.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("听不出是哪种语言，你来选一下").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(model.languageAsk, id: \.locale) { lang in
                        SoftButton(lang.name) { model.pickLanguage(lang) }
                    }
                    Menu {
                        ForEach(sourceLanguages.filter { !model.languageAsk.contains($0) }, id: \.locale) { lang in
                            Button(lang.name) { model.pickLanguage(lang) }
                        }
                    } label: {
                        Text("更多…").font(.fee(.bodySecondary, strong: true))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(Palette.secondary)
                }
            }
        } else if let fetch = model.modelFetch {
            fetchCard(fetch)
        }
    }

    /// macOS reports a speech model's download only as not started or done, so a bar that fills
    /// would sit at its start: a moving one and the time waited say it is still coming.
    private func fetchCard(_ fetch: ModelFetch) -> some View {
        let offer = model.cloud.offered ? model.cloud.service : nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView().progressViewStyle(.linear).controlSize(.small).tint(Palette.tertiary).frame(width: 64)
                Text(fetch.background ? L("正在补装 \(fetch.name) 语音模型") : L("正在下载 \(fetch.name) 语音模型"))
                    .font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let waited = Self.minutes(context.date.timeIntervalSince(fetch.since))
                Text(offer.map { L("已等 \(waited)，比平常慢。可以先交给 \($0) 听：声音会发给 \($0)，整句出字、慢 2–3 秒") }
                     ?? (fetch.background ? L("约 140 MB · 已等 \(waited) · 装好后自动判断语言") : L("约 140 MB · 已等 \(waited)")))
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let offer {
                HStack(spacing: 8) {
                    SoftButton(L("先用 \(offer) 听"), dark: true) { model.startCloud() }
                    SoftButton(L("继续等")) { model.declineCloud() }
                }
            }
        }
    }

    /// The service hears the meeting: lines come whole and a little late, and the audio leaves the Mac.
    private func cloudCard(_ service: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if model.modelFetch != nil {
                    ProgressView().progressViewStyle(.linear).controlSize(.small).tint(Palette.tertiary).frame(width: 64)
                }
                Text("\(service) 先听着").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
            }
            Text(model.modelFetch.map { L("整句出字、慢 2–3 秒，\($0.name) 模型装好后自动换回本机") } ?? L("整句出字、慢 2–3 秒，声音会发给 \(service)"))
                .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            SoftButton(model.modelFetch != nil ? L("换回等待") : L("换回本机")) { model.stopCloud() }
        }
    }

    private func cloudBackCard(_ service: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.icon(13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("语音模型装好了，已换回本机").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
            }
            Text("字幕重新边说边出，声音不再发给 \(service)").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// None of the installed models hear their language: the likely ones not installed come first
    /// (picking one downloads it and replays the start), the installed ones in case the check was wrong.
    private var notInstalledCard: some View {
        let installed = model.candidates
        let names = installed.map(\.name)
        let title = names.count == 1 ? L("听着不像 \(names[0])")
            : names.count == 2 ? L("听着不像 \(names[0]) 或 \(names[1])") : L("听着不像已装的语言")
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                Text("选了就下载它的语音模型，开头这段也会补上").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(model.languageAsk, id: \.locale) { lang in
                    SoftButton(lang.name) { model.pickLanguage(lang) }
                }
                Menu {
                    ForEach(sourceLanguages.filter { !model.languageAsk.contains($0) && !installed.contains($0) }, id: \.locale) { lang in
                        Button(lang.name) { model.pickLanguage(lang) }
                    }
                } label: {
                    Text("更多…").font(.fee(.bodySecondary, strong: true))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 10) {
                Text("其实是：").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                ForEach(installed, id: \.locale) { lang in
                    Button(lang.name) { model.pickLanguage(lang) }
                        .buttonStyle(.plain).font(.fee(.bodySecondary, strong: true))
                        .foregroundStyle(Palette.secondary).underline()
                }
            }
        }
    }

    /// The model 听不出 needed couldn't be had: why, the one thing that helps, and the languages
    /// already on the Mac to go on with meanwhile.
    private func problemCard(_ p: ModelProblem) -> some View {
        // Chosen in settings, the language isn't swapped from here.
        let installed = model.settings.sourceMode == .auto ? model.candidates.filter { $0 != p.lang } : []
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("没能下载 \(p.lang.name) 语音模型").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                if let reason = reason(p.cause) {
                    Text(reason).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                switch p.cause {
                case .disk: SoftButton(L("打开存储空间"), dark: true) { model.openStorageSettings() }
                case .dictation: SoftButton(L("打开听写设置"), dark: true) { model.openDictationSettings() }
                case .other, .limit: SoftButton(L("再试一次"), dark: true) { model.retryModel() }
                case .offline: EmptyView()
                }
                // Not offline: the service is out of reach then too.
                if p.cause != .offline, model.running, let service = model.cloud.service {
                    SoftButton(L("先用 \(service) 听")) { model.startCloud() }
                }
            }
            if !installed.isEmpty {
                HStack(spacing: 8) {
                    Text("先用已装的：").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    ForEach(installed, id: \.locale) { lang in
                        SoftButton(lang.name) { model.pickLanguage(lang) }
                    }
                }
            }
        }
    }

    private func reason(_ cause: ModelProblem.Cause) -> String? {
        switch cause {
        case .offline: return L("网络连不上，连上后会自动继续")
        case .disk: return L("这台 Mac 的磁盘空间不够了")
        case .limit: return L("这台 Mac 上的语音模型已满 5 种")
        case .dictation(let message), .other(let message?): return message
        case .other(nil): return nil
        }
    }
}

extension Notification.Name {
    /// 主窗口的键盘和菜单「显示」里的手帐项：object 是 todo / week / month / earlier / left / right / up / down / notes / transcript。
    static let plannerKey = Notification.Name("cicada.plannerKey")
    /// Debug `play:<seconds>`: the shown record plays from there.
    static let debugPlay = Notification.Name("cicada.debugPlay")
    static let debugMainSearch = Notification.Name("cicada.debugMainSearch")
    /// Debug `shareSheet:<id>`: the 分享… sheet opens for that record (no id: it closes).
    static let debugPlannerRange = Notification.Name("cicada.debugPlannerRange")
    static let debugShareSheet = Notification.Name("cicada.debugShareSheet")
}

/// 主窗口的键盘：⌘1…⌘4 分隔页、← / → 翻周（月）、↑ / ↓ 换一场会议、⌘[ / ⌘] 纪要 / 文字记录。
/// 菜单「显示」里列着同样的键（AppMenu），但按键都在这里先接走，只认主窗口，同一个键只有一个人管。
/// 方向键另外要求没有输入框或选中文字、没有弹出的表单，其余照常交给输入框、文字记录的选择和滚动。
final class PlannerKeys {
    private var monitor: Any?

    static let arrows: [UInt16: String] = [123: "left", 124: "right", 126: "up", 125: "down"]
    static let commands = ["1": "todo", "2": "week", "3": "month", "4": "earlier", "[": "notes", "]": "transcript"]

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let key: String?
            if flags == .command {
                key = Self.commands[e.charactersIgnoringModifiers ?? ""]
                guard key != nil, MainActor.assumeIsolated({ Self.isMain(e.window) }) else { return e }
            } else {
                key = Self.arrows[e.keyCode]
                guard key != nil, MainActor.assumeIsolated({ Self.applies(to: e.window, flags: e.modifierFlags) }) else { return e }
            }
            NotificationCenter.default.post(name: .plannerKey, object: key)
            return nil
        }
    }

    @MainActor static func isMain(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.contentView is NSHostingView<MainWindowView> && window.attachedSheet == nil
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// 方向键归手帐：主窗口、没按修饰键、没有表单、焦点不在可输入或可选的文字上。
    @MainActor static func applies(to window: NSWindow?, flags: NSEvent.ModifierFlags) -> Bool {
        guard isMain(window), let window,
              flags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        return !onText(window.firstResponder)
    }

    /// 输入框的字段编辑器、改这句的编辑框、文字记录里可选的文字。
    static func onText(_ r: NSResponder?) -> Bool {
        guard let r else { return false }
        return r is NSText || String(describing: type(of: r)).contains("Text")
    }
}

/// A click on the words of a transcript line plays from it, as a click elsewhere on the line does:
/// selectable text takes the mouse before SwiftUI's tap. A drag (selecting) or a double click
/// (a word) does nothing; the time and 改这句… keep their own buttons.
final class WordClick {
    private var monitor: Any?

    func install(line: @escaping () -> String?, play: @escaping (String) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            guard e.clickCount == 1, let id = line(), Self.onText(e) else { return e }
            // The text tracks the mouse until it is let go, and its mouse-up never reaches a
            // monitor: look once that tracking is over.
            let start = NSEvent.mouseLocation
            Self.whenReleased(within: 1) {
                let now = NSEvent.mouseLocation
                guard hypot(now.x - start.x, now.y - start.y) < 3, line() == id else { return }
                play(id)
            }
            return e
        }
    }

    /// Once the button is up (a click, not a press held to select): checked every 50 ms.
    private static func whenReleased(within seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if NSEvent.pressedMouseButtons & 1 == 0 { action() } else if seconds > 0.05 { whenReleased(within: seconds - 0.05, action) }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// The mouse went down on selectable text, not on a button or the row's empty space (which
    /// the row's own tap handles).
    private static func onText(_ e: NSEvent) -> Bool {
        guard let content = e.window?.contentView,
              let hit = content.hitTest(content.convert(e.locationInWindow, from: nil)) else { return false }
        return hit is NSText || String(describing: type(of: hit)).contains("TextField")
    }
}
