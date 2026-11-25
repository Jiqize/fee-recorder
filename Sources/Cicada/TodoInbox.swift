import Foundation

/// To-dos that belong to no meeting (待办板上「＋ 加一条」, shown as 手记), kept in
/// `Todos/inbox.json` beside the sessions. Same rules as a meeting's own to-dos.
@MainActor
final class TodoInbox: ObservableObject {
    @Published private(set) var items: [NoteItem] = []
    let file: URL

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder)
            .appendingPathComponent("Todos/inbox.json")
    }

    init(file: URL? = nil) {
        self.file = file ?? Self.defaultFile
        load()
    }

    func add(text: String, owner: String?, due: String?) {
        var n = MeetingNotes()
        n.todos = items
        save(n.addingTodo(text: text, owner: owner, due: due).todos)
    }

    func change(key: String, _ change: TodoChange, now: Date) {
        var n = MeetingNotes()
        n.todos = items
        // 手记都是自己加的，删除不留墓碑
        save(n.changingTodo(key: key, change, now: now).todos)
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            items = try JSONDecoder().decode([NoteItem].self, from: data)
        } catch {
            // 坏文件另存一份再从空开始，不覆盖用户的东西
            debugLog("todos: inbox unreadable, starting empty")
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let bad = file.deletingLastPathComponent().appendingPathComponent("inbox.bad-\(f.string(from: Date())).json")
            try? FileManager.default.moveItem(at: file, to: bad)
            items = []
        }
    }

    private func save(_ next: [NoteItem]) {
        guard next != items else { return }
        items = next
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
        } catch {
            debugLog("todos: inbox not saved \(error)")
        }
    }
}
