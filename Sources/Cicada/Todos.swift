import Foundation

/// Where a to-do stands. Stored as `state` on `NoteItem`; nil means open.
enum TodoState: String, Codable {
    case open, doing, done
}

/// An AI to-do the user deleted: enough to recognise it when the notes are rewritten, even in
/// other words (same moment, same owner).
struct TodoTombstone: Codable, Equatable {
    var text: String
    var t: Double?
    var owner: String?
}

/// One change the user makes to a to-do, from any place it is shown.
enum TodoChange: Equatable {
    case state(TodoState)
    case star(Bool)
    /// "yyyy-MM-dd", or nil to clear.
    case due(String?)
    /// Blank text deletes.
    case text(String)
    case owner(String?)
    case delete
}

extension NoteItem {
    /// What ticking the box makes it: open or in progress → done; done → open.
    func toggled(now: Date) -> TodoState {
        status == .done ? .open : .done
    }

    static func newTodoID() -> String { String(format: "%08x", UInt32.random(in: .min ... .max)) }
}

extension MeetingNotes {
    /// The notes with one to-do changed. Any change marks it touched, so a rewrite keeps it as is.
    func changingTodo(key: String, _ change: TodoChange, now: Date) -> MeetingNotes {
        guard let i = todos.firstIndex(where: { $0.key == key }) else { return self }
        return changingTodo(at: i, change, now: now)
    }

    /// 按位置改：页面编辑按行号找，旧记录里两条同字的待办没有 uid 时 key 会撞。
    func changingTodo(at i: Int, _ change: TodoChange, now: Date) -> MeetingNotes {
        guard todos.indices.contains(i) else { return self }
        var n = self
        var item = n.todos[i]
        switch change {
        case .delete:
            n.deleteTodo(at: i)
            return n
        case .text(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                n.deleteTodo(at: i)
                return n
            }
            // 只记第一次改之前 AI 的原文，之后再改也认得出是同一条
            if item.byUser != true, item.aiText == nil, text != item.text { item.aiText = item.text }
            item.text = text
        case .state(let s):
            item.state = s == .open ? nil : s
            item.doneAt = s == .done ? now : nil
        case .star(let on):
            item.starred = on ? true : nil
        case .due(let d):
            item.due = d.flatMap { $0.isEmpty ? nil : $0 }
        case .owner(let o):
            item.owner = o.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        item.touched = true
        n.todos[i] = item
        return n
    }

    /// A to-do the user adds: theirs by default, kept through every rewrite.
    func addingTodo(text: String, owner: String?, due: String?) -> MeetingNotes {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return self }
        var n = self
        let ids = Set(todos.compactMap(\.uid))
        var uid = NoteItem.newTodoID()
        while ids.contains(uid) { uid = NoteItem.newTodoID() }
        n.todos.append(NoteItem(text: text, owner: owner ?? "你", support: 0, uid: uid,
                                due: due, byUser: true, touched: true))
        return n
    }

    /// Gives every to-do without one a stable id; existing ids stay.
    mutating func assignTodoIDs() {
        var ids = Set(todos.compactMap(\.uid))
        for i in todos.indices where todos[i].uid == nil {
            var uid = NoteItem.newTodoID()
            while ids.contains(uid) { uid = NoteItem.newTodoID() }
            ids.insert(uid)
            todos[i].uid = uid
        }
    }

    /// AI 待办留墓碑（同字不重复），自己加的直接删。
    private mutating func deleteTodo(at i: Int) {
        let item = todos.remove(at: i)
        guard item.byUser != true else { return }
        let stone = TodoTombstone(text: item.aiText ?? item.text, t: item.t, owner: item.owner)
        var stones = removedTodos ?? []
        if !stones.contains(where: { $0.text == stone.text }) { stones.append(stone) }
        removedTodos = stones
    }
}

/// To-dos the user touched, held while a record is transcribed again (its notes are gone until
/// the new ones are written). Stored as `Session.keptTodos`.
struct KeptTodos: Codable, Equatable {
    var items: [NoteItem]
    var removed: [TodoTombstone]
}

/// Keeps the user's to-dos through a rewrite of the notes (spec › AI 重新整理时不丢东西).
enum TodoMerge {
    private static func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private static func sameMoment(_ a: Double?, _ ao: String?, _ b: Double?, _ bo: String?) -> Bool {
        guard let a, let b else { return false }
        return abs(a - b) <= 1 && ao == bo
    }

    private static func words(_ i: NoteItem) -> Set<String> { Set([i.text, i.aiText].compactMap { $0 }.map(norm)) }

    private static func sameWords(_ a: NoteItem, _ b: NoteItem) -> Bool { !words(a).isDisjoint(with: words(b)) }

    /// The same thing to do: the same words (either side's AI wording counts), or said at the same
    /// moment by the same owner. 只比文字不够：完整版会换措辞、换语言会整句换掉。
    static func same(_ a: NoteItem, _ b: NoteItem) -> Bool {
        sameWords(a, b) || sameMoment(a.t, a.owner, b.t, b.owner)
    }

    /// Deleted before: the same words as a tombstone, or the same moment and owner.
    static func buried(_ item: NoteItem, in stones: [TodoTombstone]) -> Bool {
        stones.contains { words(item).contains(norm($0.text)) || sameMoment(item.t, item.owner, $0.t, $0.owner) }
    }

    /// What a merge did with the reply's to-dos, for the log.
    struct Outcome: Equatable {
        var reply = 0, kept = 0, sameAsKept = 0, buried = 0, added = 0
    }

    /// `new` is a fresh reply. What the user touched or added comes first, as it was; the reply's
    /// to-dos follow unless they are one of those or were deleted; an untouched one keeps its id.
    /// `names`: the speakers' names the model was given. Stored to-dos may still say "说话人2"
    /// while the reply says "Ben", so they are compared as shown, and stored as they were.
    @discardableResult
    static func carry(from latest: MeetingNotes?, kept: KeptTodos? = nil, names: [Int: String] = [:],
                      into new: inout MeetingNotes) -> Outcome {
        var stones = latest?.removedTodos ?? []
        for s in kept?.removed ?? [] where !stones.contains(where: { norm($0.text) == norm(s.text) }) { stones.append(s) }

        func isUsers(_ i: NoteItem) -> Bool { i.touched == true || i.byUser == true }
        var keep = (latest?.todos ?? []).filter(isUsers)
        for k in (kept?.items ?? []).filter(isUsers) where !keep.contains(where: { same($0, k) }) { keep.append(k) }
        let untouched = (latest?.todos ?? []).filter { !isUsers($0) }

        // 只为比较换上现在的名字
        func shown(_ items: [NoteItem], _ stones: [TodoTombstone] = []) -> (items: [NoteItem], stones: [TodoTombstone]) {
            guard !names.isEmpty else { return (items, stones) }
            var n = MeetingNotes()
            n.todos = items
            n.removedTodos = stones
            let v = SpeakerLabels.named(n, names)
            return (v.todos, v.removedTodos ?? [])
        }
        let keepShown = shown(keep).items, stonesShown = shown([], stones).stones
        let untouchedShown = shown(untouched).items

        var out = Outcome(reply: new.todos.count, kept: keep.count)
        // 先按文字认；按「同一时刻 + 同一负责人」认时，一条保留的 / 一块墓碑只认领一条，且只在它没按文字认到时。
        // 否则同一句话里说的两件事（时刻、负责人都一样）勾了一件，另一件也会被吞掉。
        let replies = new.todos
        var dropped = Set<Int>(), keepClaimed = Set<Int>(), stoneClaimed = Set<Int>()
        for (i, r) in replies.enumerated() {
            if let k = keepShown.firstIndex(where: { sameWords($0, r) }) {
                dropped.insert(i); keepClaimed.insert(k); out.sameAsKept += 1
            } else if let s = stonesShown.firstIndex(where: { words(r).contains(norm($0.text)) }) {
                dropped.insert(i); stoneClaimed.insert(s); out.buried += 1
            }
        }
        for (i, r) in replies.enumerated() where !dropped.contains(i) {
            if let k = keepShown.indices.first(where: { !keepClaimed.contains($0) && sameMoment(keepShown[$0].t, keepShown[$0].owner, r.t, r.owner) }) {
                dropped.insert(i); keepClaimed.insert(k); out.sameAsKept += 1
            } else if let s = stonesShown.indices.first(where: { !stoneClaimed.contains($0) && sameMoment(r.t, r.owner, stonesShown[$0].t, stonesShown[$0].owner) }) {
                dropped.insert(i); stoneClaimed.insert(s); out.buried += 1
            }
        }
        // 放宽（2026-11-25 用户决定）：还认不到时，若那一刻（±1 秒）保留的 / 墓碑一边只剩一条、回复里也只剩这一条，
        // 不看负责人也算同一件事——会后完整版常把「未认领」改成某个人。多条候选时不猜。
        func atMoment(_ a: Double?, _ b: Double?) -> Bool {
            guard let a, let b else { return false }
            return abs(a - b) <= 1
        }
        for (i, r) in replies.enumerated() where !dropped.contains(i) {
            let peers = replies.indices.filter { !dropped.contains($0) && atMoment(replies[$0].t, r.t) }
            guard peers == [i] else { continue }
            let ks = keepShown.indices.filter { !keepClaimed.contains($0) && atMoment(keepShown[$0].t, r.t) }
            let ss = stonesShown.indices.filter { !stoneClaimed.contains($0) && atMoment(stonesShown[$0].t, r.t) }
            if ks.count == 1 {
                dropped.insert(i); keepClaimed.insert(ks[0]); out.sameAsKept += 1
            } else if ks.isEmpty, ss.count == 1 {
                dropped.insert(i); stoneClaimed.insert(ss[0]); out.buried += 1
            }
        }
        var used = Set(keep.compactMap(\.uid))
        var added: [NoteItem] = []
        for (i, var item) in replies.enumerated() where !dropped.contains(i) {
            // 没动过的：同字优先，其次同一时刻 + 同一负责人；沿用 id、更早的时间，回复没带截止日时留住原来的
            let j = untouchedShown.firstIndex(where: { sameWords($0, item) && !used.contains($0.uid ?? "") })
                ?? untouchedShown.firstIndex(where: { same($0, item) && !used.contains($0.uid ?? "") })
            if let j {
                let old = untouched[j]
                if let uid = old.uid { item.uid = uid; used.insert(uid) }
                item.t = [item.t, old.t].compactMap { $0 }.min()
                if item.due == nil { item.due = old.due }
            }
            added.append(item)
        }
        out.added = added.count
        new.todos = keep + added
        new.removedTodos = stones.isEmpty ? nil : stones
        new.assignTodoIDs()
        return out
    }
}

/// A to-do's deadline: stored as "yyyy-MM-dd" (a calendar day, no time), shown counted from today.
enum TodoDue {
    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var c = Calendar(identifier: .gregorian)
        c.timeZone = calendar.timeZone
        f.calendar = c
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }

    /// The start of that day, or nil when it isn't a real yyyy-MM-dd.
    static func date(_ s: String, calendar: Calendar = .current) -> Date? {
        let f = formatter(calendar)
        // 严格比对回写，挡掉 2026-13-40 这类被宽松解析的日期
        guard let d = f.date(from: s), f.string(from: d) == s else { return nil }
        return d
    }

    static func string(_ d: Date, calendar: Calendar = .current) -> String { formatter(calendar).string(from: d) }

    /// 今天 / 明天 / 周几（本周内）/ 3月6日; past days are 逾期 N 天.
    static func label(_ due: String, today: Date, calendar: Calendar = .current) -> (text: String, overdue: Bool) {
        guard let d = date(due, calendar: calendar) else { return (due, false) }
        let start = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: d)).day ?? 0
        if days < 0 { return (L("逾期 \(-days) 天"), true) }
        if days == 0 { return (L("今天"), false) }
        if days == 1 { return (L("明天"), false) }
        if calendar.isDate(d, equalTo: start, toGranularity: .weekOfYear) { return (dateText(d, "EEE"), false) }
        return (dateText(d, "MMMd"), false)
    }
}

/// A to-do as exported: Markdown checkboxes, or ballot boxes for Word and 复制全文 (a checkbox
/// doesn't survive a paste). ▸ is in progress, ★ starred, the deadline goes last.
enum TodoText {
    private static func rest(_ item: NoteItem) -> String {
        let star = item.isStarred ? "★ " : ""
        let due = item.due.flatMap { TodoDue.date($0) }.map { L("（截止 \(dateText($0, "MMMd"))）") } ?? ""
        return star + item.withOwner + due
    }

    static func markdown(_ item: NoteItem) -> String {
        switch item.status {
        case .open: "- [ ] " + rest(item)
        case .doing: "- [ ] ▸ " + rest(item)
        case .done: "- [x] " + rest(item)
        }
    }

    static func plain(_ item: NoteItem) -> String {
        switch item.status {
        case .open: "☐ " + rest(item)
        case .doing: "▸ " + rest(item)
        case .done: "☑ " + rest(item)
        }
    }
}
