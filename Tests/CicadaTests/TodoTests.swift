import Foundation
import Testing
@testable import Cicada

@Suite struct TodoTests {
    private let day = Date(timeIntervalSince1970: 1_795_600_000)

    /// 一条结论 + 两条 AI 待办 + 一条自己加的。
    private var notes: MeetingNotes {
        var n = MeetingNotes()
        n.conclusions = [NoteItem(text: "锁定 3月3日", owner: nil, support: 2, t: 11)]
        n.todos = [NoteItem(text: "周五前签署", owner: "说话人2", support: 1, t: 11, uid: "aaaa0001"),
                   NoteItem(text: "改尺码表", owner: "你", support: 1, t: 80, uid: "aaaa0002"),
                   NoteItem(text: "约摄影师", owner: "你", support: 0, uid: "bbbb0001", byUser: true, touched: true)]
        return n
    }

    // MARK: 数据与兼容

    @Test func oldJSONDecodesAsAnOpenTodo() throws {
        let item = try JSONDecoder().decode(NoteItem.self, from: Data(#"{"text":"a","support":1}"#.utf8))
        #expect(item.status == .open)
        #expect(item.due == nil)
        #expect(!item.isStarred)
        #expect(item.key == "a" && item.id == "a")
    }

    @Test func emptyNewFieldsAreNotWritten() throws {
        let data = try JSONEncoder().encode(NoteItem(text: "a", owner: nil, support: 1))
        let json = String(decoding: data, as: UTF8.self)
        for key in ["state", "due", "starred", "uid", "byUser", "touched", "aiText", "doneAt"] {
            #expect(!json.contains("\"\(key)\""), "\(key) should be left out")
        }
    }

    @Test func notesWithoutRemovedTodosStillDecode() throws {
        let n = try JSONDecoder().decode(MeetingNotes.self, from: Data(#"{"summary":"s","topics":[],"conclusions":[],"todos":[{"text":"a","support":1}],"terms":[],"covered":0,"final":false}"#.utf8))
        #expect(n.removedTodos == nil)
        #expect(n.todos.first?.status == .open)
    }

    @Test func idUsesTheStableIDWhenThereIsOne() {
        #expect(notes.todos[0].key == "aaaa0001" && notes.todos[0].id == "aaaa0001")
        #expect(notes.conclusions[0].id == "锁定 3月3日")
    }

    // MARK: 单条改动

    @Test func doneRecordsWhenAndOpenClearsIt() {
        let n = notes.changingTodo(key: "aaaa0001", .state(.done), now: day)
        #expect(n.todos[0].status == .done)
        #expect(n.todos[0].doneAt == day)
        #expect(n.todos[0].touched == true)
        let m = n.changingTodo(key: "aaaa0001", .state(.open), now: day)
        #expect(m.todos[0].status == .open)
        #expect(m.todos[0].doneAt == nil)
    }

    @Test func everyChangeMarksTheTodoTouched() {
        let changes: [TodoChange] = [.state(.doing), .star(true), .due("2026-11-25"), .text("新字"), .owner("Ben")]
        for c in changes {
            #expect(notes.changingTodo(key: "aaaa0002", c, now: day).todos[1].touched == true, "\(c)")
        }
        let n = notes.changingTodo(key: "aaaa0002", .star(true), now: day)
            .changingTodo(key: "aaaa0002", .due("2026-11-25"), now: day)
            .changingTodo(key: "aaaa0002", .owner(nil), now: day)
        #expect(n.todos[1].isStarred && n.todos[1].due == "2026-11-25" && n.todos[1].owner == nil)
        #expect(n.changingTodo(key: "aaaa0002", .due(nil), now: day).todos[1].due == nil)
    }

    @Test func firstTextChangeKeepsTheAIOriginal() {
        let n = notes.changingTodo(key: "aaaa0001", .text("新字"), now: day)
        #expect(n.todos[0].text == "新字")
        #expect(n.todos[0].aiText == "周五前签署")
        let m = n.changingTodo(key: "aaaa0001", .text("再改"), now: day)
        #expect(m.todos[0].text == "再改")
        #expect(m.todos[0].aiText == "周五前签署", "still the first AI wording")
    }

    @Test func blankTextDeletes() {
        let n = notes.changingTodo(key: "aaaa0001", .text("  "), now: day)
        #expect(n.todos.map(\.key) == ["aaaa0002", "bbbb0001"])
    }

    @Test func deletingAnAITodoLeavesATombstone() {
        let n = notes.changingTodo(key: "aaaa0001", .delete, now: day)
        #expect(n.todos.count == 2)
        #expect(n.removedTodos == [TodoTombstone(text: "周五前签署", t: 11, owner: "说话人2")])
        // 改过字再删：墓碑记 AI 的原文
        let m = notes.changingTodo(key: "aaaa0002", .text("改尺码表 v2"), now: day)
            .changingTodo(key: "aaaa0002", .delete, now: day)
        #expect(m.removedTodos == [TodoTombstone(text: "改尺码表", t: 80, owner: "你")])
    }

    @Test func tombstonesDoNotRepeatTheSameText() {
        var base = notes
        base.removedTodos = [TodoTombstone(text: "周五前签署", t: 11, owner: "说话人2")]
        let n = base.changingTodo(key: "aaaa0001", .delete, now: day)
        #expect(n.removedTodos?.count == 1)
    }

    @Test func deletingYourOwnTodoLeavesNoTombstone() {
        let n = notes.changingTodo(key: "bbbb0001", .delete, now: day)
        #expect(n.todos.count == 2)
        #expect(n.removedTodos == nil)
    }

    @Test func anUnknownKeyChangesNothing() {
        #expect(notes.changingTodo(key: "nope", .state(.done), now: day) == notes)
    }

    // MARK: 旧的编辑入口

    @Test func pageEditsOfATodoGoThroughTheSameRules() {
        let n = notes.editing(.item(1), text: "改过")
        #expect(n.todos[0].text == "改过")
        #expect(n.todos[0].touched == true)
        #expect(n.todos[0].aiText == "周五前签署")
        let o = notes.editing(.item(1), text: "周五前签署", owner: .some("Emma"))
        #expect(o.todos[0].owner == "Emma" && o.todos[0].touched == true && o.todos[0].aiText == nil)
        let m = notes.editing(.item(1), text: "")
        #expect(m.removedTodos == [TodoTombstone(text: "周五前签署", t: 11, owner: "说话人2")])
        #expect(notes.editing(.item(1), text: "周五前签署") == notes, "saving unchanged text changes nothing")
    }

    // MARK: 自己加、补 id、点方框

    @Test func addingATodoIsYoursByDefault() {
        let n = notes.addingTodo(text: " 约摄影师 ", owner: nil, due: nil)
        let added = n.todos.last!
        #expect(n.todos.count == 4)
        #expect(added.text == "约摄影师")
        #expect(added.byUser == true && added.touched == true)
        #expect(added.owner == "你")
        #expect(isHexID(added.uid))
        #expect(notes.addingTodo(text: "x", owner: "Ben", due: "2026-11-25").todos.last.map { $0.owner == "Ben" && $0.due == "2026-11-25" } == true)
        #expect(notes.addingTodo(text: "  ", owner: nil, due: nil) == notes)
    }

    @Test func missingIDsAreFilledAndKeptOnes() {
        var n = MeetingNotes()
        n.todos = [NoteItem(text: "a", owner: nil, support: 1), NoteItem(text: "b", owner: nil, support: 1, uid: "keep0001")]
        n.assignTodoIDs()
        #expect(isHexID(n.todos[0].uid))
        #expect(n.todos[1].uid == "keep0001")
    }

    @Test func tickingTheBoxGoesToDoneAndBack() {
        var item = NoteItem(text: "a", owner: nil, support: 1)
        #expect(item.toggled(now: day) == .done)
        item.state = .doing
        #expect(item.toggled(now: day) == .done)
        item.state = .done
        #expect(item.toggled(now: day) == .open)
    }

    private func isHexID(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.count == 8 && s.allSatisfy { "0123456789abcdef".contains($0) }
    }
}
