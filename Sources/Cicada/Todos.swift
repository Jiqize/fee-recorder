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
