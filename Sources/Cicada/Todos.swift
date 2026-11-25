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

    /// The same thing to do: the same words (either side's AI wording counts), or said at the same
    /// moment by the same owner. 只比文字不够：完整版会换措辞、换语言会整句换掉。
    static func same(_ a: NoteItem, _ b: NoteItem) -> Bool {
        let aw = Set([a.text, a.aiText].compactMap { $0 }.map(norm))
        let bw = Set([b.text, b.aiText].compactMap { $0 }.map(norm))
        return !aw.isDisjoint(with: bw) || sameMoment(a.t, a.owner, b.t, b.owner)
    }

    /// Deleted before: the same words as a tombstone, or the same moment and owner.
    static func buried(_ item: NoteItem, in stones: [TodoTombstone]) -> Bool {
        let words = Set([item.text, item.aiText].compactMap { $0 }.map(norm))
        return stones.contains { words.contains(norm($0.text)) || sameMoment(item.t, item.owner, $0.t, $0.owner) }
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
        var used = Set(keep.compactMap(\.uid))
        var added: [NoteItem] = []
        for var item in new.todos {
            if keepShown.contains(where: { same($0, item) }) { out.sameAsKept += 1; continue }
            if buried(item, in: stonesShown) { out.buried += 1; continue }
            if let j = untouchedShown.firstIndex(where: { same($0, item) }) {
                let old = untouched[j]
                if let uid = old.uid, !used.contains(uid) { item.uid = uid; used.insert(uid) }
                item.t = [item.t, old.t].compactMap { $0 }.min()
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
