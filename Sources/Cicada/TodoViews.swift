import SwiftUI

// MARK: - 一条待办

/// 角色栏里的状态：☐ 手画方框 / ▸ 红铅笔 / ☑ 绿勾（勾 0.2 秒画出来，减少动态效果时直接出现）。
struct TodoBox: View {
    let state: TodoState
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if state == .doing {
                Text("▸").font(.fee(.body, strong: true)).foregroundStyle(Palette.link)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state == .done ? Palette.tertiary : Palette.body, lineWidth: 1.5)
                    .frame(width: size, height: size).rotationEffect(.degrees(-3))
                TickShape().trim(from: 0, to: state == .done ? drawn : 0)
                    .stroke(Palette.ok, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: size - 1, height: size + 1).offset(x: 2, y: -1)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .onChange(of: state) { old, new in
            guard new == .done, old != .done, !reduceMotion else { drawn = 1; return }
            drawn = 0
            withAnimation(.easeOut(duration: 0.2)) { drawn = 1 }
        }
    }
}

/// 一笔铅笔勾。
private struct TickShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 1))
        return p
    }
}

/// 一条待办：方框、文字和负责人、行尾的截止日 / 来源会议 / 星标。点方框打勾，点文字原地改，
/// 右键改状态、星标、截止日、负责人或删除。所有改动都交给 `change`（AppModel.changeTodo）。
struct TodoRow: View {
    let item: NoteItem
    /// 来源会议名（待办板上），点了调 `openSource`；手记写 L("手记")。
    var meeting: String? = nil
    var showOwner = true
    /// 便利贴、实时纪要窗：横排紧凑，不显示来源，不能改截止日。
    var compact = false
    /// 实时纪要窗：只能勾，不显示星标，不能改字、不弹菜单。
    var tickOnly = false
    let change: (TodoChange) -> Void
    var openSource: (() -> Void)? = nil

    @State private var editing = false
    @State private var draft = ""
    @State private var pickingDue = false
    @State private var due = Date()
    @State private var editingOwner = false
    @State private var ownerDraft = ""
    @FocusState private var focused: Bool

    private var done: Bool { item.status == .done }

    var body: some View {
        Group {
            if compact { compactRow } else { ruledRow }
        }
        .contextMenu { if !tickOnly { menu } }
        .popover(isPresented: $pickingDue, arrowEdge: .bottom) { duePicker }
        .popover(isPresented: $editingOwner, arrowEdge: .bottom) { ownerEditor }
    }

    // MARK: 两种排法

    private var ruledRow: some View {
        GutterRow(gutter: {
            box.frame(height: PaperMetrics.pitch).padding(.trailing, 10)
        }, content: {
            if editing { editor } else { words.ruledText(.body).fixedSize(horizontal: false, vertical: true).onTapGesture(perform: startEditing) }
        }, trailing: {
            HStack(spacing: 14) {
                dueLabel.font(.fee(.bodySecondary))
                if let meeting { source(meeting) }
                if !tickOnly { star }
            }
            .frame(height: PaperMetrics.pitch)
        })
    }

    private var compactRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            box.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            if editing {
                editor
            } else {
                words.font(.fee(.bodySecondary)).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading).onTapGesture(perform: startEditing)
            }
            Spacer(minLength: 4)
            dueLabel.font(.fee(.label)).fixedSize()
            if !tickOnly, item.isStarred { star }
        }
    }

    // MARK: 零件

    private var box: some View {
        Button { change(.state(item.toggled(now: Date()))) } label: { TodoBox(state: item.status, size: compact ? 12 : 14) }
            .buttonStyle(.plain)
            .help(done ? L("标成没做完") : L("标成做完了"))
            .accessibilityLabel(done ? L("标成没做完") : L("标成做完了"))
    }

    /// 文字 + 灰字负责人；做完了划线变浅；自己加的是黄纸条蓝字。
    private var words: some View {
        let ink: Color = done ? Palette.tertiary : (item.byUser == true ? Palette.inkBlue : Palette.ink)
        var t = Text(item.text).foregroundStyle(ink).strikethrough(done, color: Palette.tertiary)
        if showOwner {
            if item.owner == nil || item.owner == "未识别" {
                t = t + Text(" · " + L("未认领")).font(.fee(.label)).foregroundStyle(Palette.placeholder)
            } else if let o = item.ownerShown {
                t = t + Text(" · " + o).font(.fee(.label)).foregroundStyle(Palette.secondary)
            }
        }
        return t
            .padding(.horizontal, item.byUser == true ? 6 : 0)
            .background(item.byUser == true ? Palette.stickyYellow : .clear)
            .help(tickOnly ? "" : L("点一下修改"))
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let d = item.due {
            let l = TodoDue.label(d, today: Date())
            Text(l.text).foregroundStyle(done ? Palette.tertiary : (l.overdue ? Palette.error : Palette.secondary))
        }
    }

    private func source(_ name: String) -> some View {
        Button { openSource?() } label: {
            Text(name).font(.fee(.label)).foregroundStyle(openSource == nil ? Palette.secondary : Palette.link)
                .lineLimit(1).truncationMode(.tail)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.link.opacity(0.4)).frame(height: 1).offset(y: 1).opacity(openSource == nil ? 0 : 1)
                }
                .frame(maxWidth: 140, alignment: .trailing)
        }
        .buttonStyle(.plain).disabled(openSource == nil)
        .help(openSource == nil ? "" : L("打开这句话"))
    }

    private var star: some View {
        Button { change(.star(!item.isStarred)) } label: {
            Text(item.isStarred ? "★" : "☆").font(.fee(.body)).foregroundStyle(item.isStarred ? Palette.star : Palette.placeholder)
        }
        .buttonStyle(.plain).disabled(tickOnly)
        .help(item.isStarred ? L("去星") : L("加星"))
    }

    @ViewBuilder
    private var menu: some View {
        Button(L("没开始")) { change(.state(.open)) }.disabled(item.status == .open)
        Button(L("进行中")) { change(.state(.doing)) }.disabled(item.status == .doing)
        Button(L("做完了")) { change(.state(.done)) }.disabled(done)
        Divider()
        Button(item.isStarred ? L("去星") : L("加星")) { change(.star(!item.isStarred)) }
        if !compact {
            Button(L("设截止日…")) {
                due = item.due.flatMap { TodoDue.date($0) } ?? Date()
                pickingDue = true
            }
        }
        if item.due != nil { Button(L("清除截止日")) { change(.due(nil)) } }
        Button(L("改负责人…")) { ownerDraft = item.owner ?? ""; editingOwner = true }
        Divider()
        Button(L("删除")) { change(.delete) }
    }

    // MARK: 原地改

    private func startEditing() {
        guard !tickOnly else { return }
        draft = item.text
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private var editor: some View {
        TextField(L("待办"), text: $draft, axis: .vertical)
            .textFieldStyle(.plain).focusEffectDisabled()
            .font(.fee(compact ? .bodySecondary : .body)).lineLimit(1...4)
            .focused($focused)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Palette.inkBlue : Palette.hairline).frame(height: focused ? 1.5 : 1).offset(y: 2)
            }
            .onSubmit {
                // 清空即删除（.text 的空白规则）
                if draft != item.text { change(.text(draft)) }
                editing = false
            }
            .onExitCommand { editing = false }
            .help(L("⏎ 保存 · esc 取消"))
    }

    private var duePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("", selection: $due, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
            HStack {
                Button(L("清除")) { change(.due(nil)); pickingDue = false }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary)
                Spacer()
                Button(L("确定")) { change(.due(TodoDue.string(due))); pickingDue = false }
                    .buttonStyle(.plain).foregroundStyle(Palette.accentInk)
                    .keyboardShortcut(.defaultAction)
            }
            .font(.fee(.bodySecondary))
        }
        .padding(12)
    }

    private var ownerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("负责人"), text: $ownerDraft)
                .textFieldStyle(.plain).font(.fee(.body)).frame(width: 160)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1).offset(y: 2) }
                .onSubmit { saveOwner() }
            Text("⏎ 保存 · esc 取消").font(.fee(.label)).foregroundStyle(Palette.tertiary)
        }
        .padding(12)
    }

    private func saveOwner() {
        let o = ownerDraft.trimmingCharacters(in: .whitespaces)
        change(.owner(o.isEmpty ? nil : o))
        editingOwner = false
    }
}

// MARK: - 加一条

/// 「＋ 加一条」：点开成下划线输入框，⏎ 加上（可以接着加），esc 收起。
struct TodoAddLine: View {
    let add: (String) -> Void
    var compact = false
    /// 一出现就是输入框（待办板页眉的「＋ 加一条」）。
    var startOpen = false
    @State private var open = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if open {
                TextField(L("要做的事"), text: $draft)
                    .textFieldStyle(.plain).focusEffectDisabled()
                    .font(.fee(compact ? .bodySecondary : .body)).foregroundStyle(Palette.inkBlue)
                    .focused($focused)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.inkBlue).frame(height: 1.5).offset(y: 2) }
                    .onSubmit {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { open = false } else { add(t); draft = "" }
                    }
                    .onExitCommand { open = false; draft = "" }
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                Button { open = true } label: {
                    (Text("＋ ").foregroundStyle(Palette.link).fontWeight(.semibold) + Text("加一条").foregroundStyle(Palette.secondary))
                        .font(.fee(compact ? .bodySecondary : .body))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: compact ? nil : PaperMetrics.pitch)
        .onAppear { if startOpen { open = true } }
    }
}

// MARK: - 待办板

/// 左栏搜索框下钉着的粉色索引卡：「待办 · 我的 N 条没做完 · M 条逾期」，点开右边换成待办板。
struct TodoIndexCard: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var inbox: TodoInbox
    let selected: Bool
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mine = TodoBoard.items(sessions: store.sessions, inbox: inbox.items).filter { TodoBoard.isMine($0.item) }
        let c = TodoBoard.counts(mine, today: Date())
        return Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text("待办").font(.fee(.body, strong: true)).foregroundStyle(Palette.link)
                (Text(c.open == 0 ? L("我的都做完了") : L("我的 \(c.open) 条没做完")).foregroundStyle(Palette.secondary)
                 + Text(c.overdue > 0 ? " · " + L("\(c.overdue) 条逾期") : "").foregroundStyle(Palette.error))
                    .font(.fee(.bodySecondary)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 10)
            .background(Palette.stickyPink)
            .paperShadow(deeper: selected)
            .overlay(alignment: .top) { Pin(active: true).offset(y: -4) }
            .tilted(selected ? 0 : -1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("打开待办板"))
    }
}

/// 主窗口详情页的待办板：一整张横线纸，页眉（菲比 + 标题 + 统计）、「我的 / 别人的」、分组的待办行、页脚。
struct TodoBoardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore
    @ObservedObject var inbox: TodoInbox
    /// 打开那场会议的文字记录，跳到出处那句。
    let openMeeting: (String, Double?) -> Void
    /// 整页渲染（调试截图）时不放进 ScrollView。
    var scrolls = true

    private var tab: String { model.todoBoardTab }
    @State private var showDone = false
    @State private var adding = false
    @State private var meetingFilter: String?
    @State private var ownerFilter: String?
    @State private var query = ""

    /// 说话人显示成名字（存的可能还是「说话人2」）；uid 不变，改动照样找得到。
    private var all: [BoardItem] {
        let named = store.sessions.map { s -> Session in
            var s = s
            s.notes = s.notes.map { SpeakerLabels.named($0, SpeakerLabels.names(s)) }
            return s
        }
        return TodoBoard.items(sessions: named, inbox: inbox.items)
    }

    private var today: Date { Date() }

    var body: some View {
        let items = all
        let mineAll = items.filter { TodoBoard.isMine($0.item) }
        let c = TodoBoard.counts(mineAll, today: today)
        let shown = TodoBoard.filter(items, meeting: meetingFilter, owner: ownerFilter, query: query)
        let mood: FeebeeMood = c.overdue > 0 ? .error : (c.open == 0 ? .done : .writing)
        return VStack(spacing: 0) {
            Group {
                if scrolls {
                    ScrollView { page(items: items, shown: shown, counts: c) }
                } else {
                    page(items: items, shown: shown, counts: c)
                }
            }
            .overlay(alignment: .topTrailing) {
                Polaroid(caption: c.open == 0 ? L("菲比 · 都做完了") : L("菲比 · 还有 \(c.open) 条要做")) {
                    FeebeeView(mood: mood, size: 168)
                }
                .frame(width: 190).rotationEffect(.degrees(2))
                .padding(.top, PaperMetrics.pitch * 3).padding(.trailing, 36)
            }
            NotebookFooter(status: c.open == 0 ? L("都做完了")
                           : c.overdue > 0 ? L("还有 \(c.open) 条 · \(c.overdue) 条逾期") : L("还有 \(c.open) 条"),
                           done: c.open == 0, query: $query,
                           placeholder: L("在待办里找…"),
                           hint: L("⌘F 搜索 · 点方框打勾 · 右键「进行中」· 点会议名跳到原话"))
                .padding(.leading, PaperMetrics.marginX).padding(.bottom, 4)
        }
    }

    private func page(items: [BoardItem], shown: [BoardItem], counts c: (open: Int, overdue: Int, dueToday: Int, thisWeek: Int)) -> some View {
        let mine = shown.filter { TodoBoard.isMine($0.item) }
        let others = shown.filter { !TodoBoard.isMine($0.item) }
        return VStack(alignment: .leading, spacing: 0) {
            header(c)
            tabs(mine: mine.filter { $0.item.status != .done }.count,
                 others: others.filter { $0.item.status != .done }.count, items: items)
            if meetingFilter != nil || ownerFilter != nil { filterStrip(items) }
            if adding {
                GutterRow { TodoAddLine(add: { addToInbox($0) }, startOpen: true) }
            }
            Color.clear.frame(height: PaperMetrics.pitch)
            if items.isEmpty {
                empty
            } else if tab == "mine" {
                mineList(mine)
            } else {
                othersList(others)
            }
        }
        // 右上角留给拍立得
        .padding(.trailing, 230)
        .notebookColumn()
    }

    // MARK: 页眉

    private func header(_ c: (open: Int, overdue: Int, dueToday: Int, thisWeek: Int)) -> some View {
        GutterRow(gutter: {
            FeebeeView(mood: .writing, size: 46).frame(height: PaperMetrics.pitch * 2, alignment: .top).padding(.trailing, 6)
        }, content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("待办").font(.fee(.display, strong: true)).foregroundStyle(Palette.ink)
                    .frame(height: PaperMetrics.pitch * 2, alignment: .bottom)
                (Text(L("没做完 \(c.open)")).foregroundStyle(Palette.secondary)
                 + Text(" · ").foregroundStyle(Palette.secondary)
                 + Text(L("逾期 \(c.overdue)")).foregroundStyle(c.overdue > 0 ? Palette.error : Palette.secondary)
                 + Text(" · " + L("本周到期 \(c.thisWeek)")).foregroundStyle(Palette.secondary))
                    .font(.fee(.bodySecondary)).frame(height: PaperMetrics.pitch)
            }
        })
    }

    private func tabs(mine: Int, others: Int, items: [BoardItem]) -> some View {
        GutterRow {
            HStack(spacing: 20) {
                NotebookTab(title: L("我的"), on: tab == "mine", count: mine) { model.todoBoardTab = "mine" }
                NotebookTab(title: L("别人的"), on: tab == "others", count: others) { model.todoBoardTab = "others" }
                Spacer(minLength: 12)
                Menu {
                    ForEach(meetings(items), id: \.id) { m in Button(m.title) { meetingFilter = m.id; ownerFilter = nil } }
                } label: { NotebookWord { Text("按会议") } }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Menu {
                    ForEach(owners(items), id: \.raw) { o in Button(o.shown) { ownerFilter = o.raw; meetingFilter = nil } }
                } label: { NotebookWord { Text("按人") } }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Button { adding.toggle() } label: { NotebookWord { Text("＋ 加一条") } }.buttonStyle(.plain)
            }
        }
    }

    private func meetings(_ items: [BoardItem]) -> [(id: String, title: String)] {
        var seen = Set<String>(), out: [(id: String, title: String)] = []
        for b in items { if let id = b.sessionID, let t = b.meeting, seen.insert(id).inserted { out.append((id, t)) } }
        return out
    }

    private func owners(_ items: [BoardItem]) -> [(raw: String, shown: String)] {
        var seen = Set<String>(), out: [(raw: String, shown: String)] = []
        for b in items { if let o = b.item.owner, seen.insert(o).inserted { out.append((o, b.item.ownerShown ?? o)) } }
        return out
    }

    /// 标题下的小牛皮纸条「只看：春季上新计划会 ×」。
    private func filterStrip(_ items: [BoardItem]) -> some View {
        let name = meetingFilter.flatMap { id in meetings(items).first { $0.id == id }?.title }
            ?? ownerFilter.flatMap { o in owners(items).first { $0.raw == o }?.shown } ?? ""
        return GutterRow {
            Button { meetingFilter = nil; ownerFilter = nil } label: {
                KraftTag(text: L("只看：\(name)"), note: "×").rotationEffect(.degrees(-1))
            }
            .buttonStyle(.plain).help(L("看全部")).frame(height: PaperMetrics.pitch)
        }
    }

    // MARK: 列表

    private func row(_ b: BoardItem, showOwner: Bool) -> some View {
        TodoRow(item: b.item, meeting: b.meeting ?? L("手记"), showOwner: showOwner,
                change: { [model] c in model.changeTodo(b.ref, c) },
                openSource: b.sessionID.map { id in { openMeeting(id, b.item.t) } })
    }

    private func heading(_ title: String, color: Color = Palette.ink) -> some View {
        GutterRow {
            HStack(spacing: 8) {
                Text(title).font(.fee(.section)).foregroundStyle(color)
                WavyRule(width: 70)
            }
            .frame(height: PaperMetrics.pitch)
        }
    }

    private static func title(_ g: TodoGroup) -> String {
        switch g {
        case .overdue: L("逾期")
        case .today: L("今天")
        case .thisWeek: L("这周")
        case .later: L("以后")
        case .noDate: L("没有截止日")
        case .done: L("做完了")
        }
    }

    @ViewBuilder
    private func mineList(_ mine: [BoardItem]) -> some View {
        let groups = TodoBoard.groups(mine, today: today)
        let open = groups.filter { $0.0 != .done }
        // 「我的」里只有未认领的写负责人
        ForEach(open, id: \.0) { g, list in
            heading(Self.title(g), color: g == .overdue ? Palette.error : Palette.ink)
            ForEach(list) { b in row(b, showOwner: b.item.owner == nil || b.item.owner == "未识别") }
            if g == .noDate { GutterRow { TodoAddLine(add: { addToInbox($0) }) } }
        }
        if !open.contains(where: { $0.0 == .noDate }) { GutterRow { TodoAddLine(add: { addToInbox($0) }) } }
        if let done = groups.first(where: { $0.0 == .done })?.1 {
            Color.clear.frame(height: PaperMetrics.pitch)
            if showDone {
                Button { showDone = false } label: { heading(Self.title(.done), color: Palette.secondary) }.buttonStyle(.plain)
                ForEach(done) { b in row(b, showOwner: b.item.owner == nil || b.item.owner == "未识别") }
            } else {
                GutterRow {
                    Button { showDone = true } label: {
                        Text(L("做完了 \(done.count) 条 ›")).font(.fee(.body)).foregroundStyle(Palette.secondary)
                            .frame(height: PaperMetrics.pitch).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func othersList(_ others: [BoardItem]) -> some View {
        let people = TodoBoard.byOwner(others)
        if people.isEmpty {
            GutterRow { Text("别人那里没有没做完的").font(.fee(.body)).foregroundStyle(Palette.secondary).frame(height: PaperMetrics.pitch) }
        }
        ForEach(people, id: \.owner) { p in
            GutterRow(gutter: { avatar(p.owner, from: p.items.first) }, content: {
                HStack(spacing: 8) {
                    Text(p.owner).font(.fee(.section)).foregroundStyle(Palette.ink)
                    WavyRule(width: 70)
                }
                .frame(height: PaperMetrics.pitch)
            })
            ForEach(p.items) { b in row(b, showOwner: false) }
        }
    }

    /// 说话人头像：按名字在来源会议里找编号，找不到画圆圈。
    private func avatar(_ name: String, from b: BoardItem?) -> some View {
        var number: Int?
        if let id = b?.sessionID, let s = store.session(id) {
            number = SpeakerLabels.names(s).first { $0.value == name }?.key
            if number == nil, let raw = b?.item.owner, raw.hasPrefix("说话人") {
                number = Int(raw.dropFirst(3).trimmingCharacters(in: .whitespaces))
            }
        }
        let color = number.map { SpeakerColor.ink($0) } ?? Palette.secondary
        return SpeakerAvatar(text: name, color: color, image: Illustration.speaker(number, me: false))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            GutterRow { Text("还没有待办").font(.fee(.section)).foregroundStyle(Palette.ink).frame(height: PaperMetrics.pitch) }
            GutterRow { Text("开会时说到要做的事，会自动记在这里").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).frame(height: PaperMetrics.pitch) }
            GutterRow { TodoAddLine(add: { addToInbox($0) }) }
        }
    }

    private func addToInbox(_ text: String) {
        model.addTodo(to: nil, text: text, owner: nil, due: nil)
    }
}
