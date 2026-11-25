import Foundation
import Testing
@testable import Cicada

/// 手记：不属于任何会议的待办，存在 Todos/inbox.json。
@MainActor @Suite struct TodoInboxTests {
    private func dir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-inbox-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func addedTodosAreReadBack() {
        let file = dir().appendingPathComponent("inbox.json")
        TodoInbox(file: file).add(text: "约摄影师", owner: nil, due: nil)
        let again = TodoInbox(file: file)
        #expect(again.items.count == 1)
        #expect(again.items.first?.owner == "你")
        #expect(again.items.first?.byUser == true)
    }

    @Test func changesAreSaved() {
        let file = dir().appendingPathComponent("inbox.json")
        let inbox = TodoInbox(file: file)
        inbox.add(text: "约摄影师", owner: nil, due: nil)
        inbox.change(key: inbox.items[0].key, .state(.done), now: Date())
        #expect(TodoInbox(file: file).items.first?.status == .done)
        inbox.change(key: inbox.items[0].key, .delete, now: Date())
        #expect(TodoInbox(file: file).items.isEmpty)
    }

    @Test func aBrokenFileIsSetAsideNotOverwritten() throws {
        let d = dir()
        let file = d.appendingPathComponent("inbox.json")
        try Data("not json".utf8).write(to: file)
        let inbox = TodoInbox(file: file)
        #expect(inbox.items.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: d.path)
        #expect(names.contains { $0.hasPrefix("inbox.bad-") && $0.hasSuffix(".json") })
        #expect(!names.contains("inbox.json"))
    }
}

/// 待办板：汇总所有会议 + 手记，「我的」按截止日分组。
@Suite struct TodoBoardTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }
    private func day(_ s: String) -> Date { TodoDue.date(s, calendar: calendar)! }
    private var today: Date { day("2026-11-25").addingTimeInterval(10 * 3600) }

    private func todo(_ text: String, owner: String? = "你", due: String? = nil, t: Double? = nil, uid: String) -> NoteItem {
        NoteItem(text: text, owner: owner, support: 1, t: t, uid: uid, due: due)
    }

    private func session(_ id: String, _ title: String, _ date: String, _ todos: [NoteItem]) -> Session {
        var s = Session(id: id, title: title, startedAt: day(date).addingTimeInterval(10 * 3600), endedAt: nil, lines: [], hasAudio: false)
        s.renamed = true
        var n = MeetingNotes()
        n.summary = "s"
        n.todos = todos
        s.notes = n
        return s
    }

    private var sessions: [Session] {
        [session("A", "春季上新计划会", "2026-11-20", [todo("改尺码表", due: "2026-11-23", uid: "a1"), todo("发样衣", due: "2026-11-25", uid: "a2")]),
         session("B", "面料供应商周会", "2026-11-18", [todo("订影棚", due: "2026-11-27", uid: "b1"), todo("对账", due: "2026-12-06", uid: "b2")])]
    }
    private var inbox: [NoteItem] { [NoteItem(text: "约摄影师", owner: "你", support: 0, uid: "i1", byUser: true, touched: true)] }

    @Test func gathersEveryMeetingAndTheInbox() {
        let items = TodoBoard.items(sessions: sessions, inbox: inbox)
        #expect(items.count == 5)
        #expect(items.first { $0.ref == .inbox(key: "i1") }?.meeting == nil)
        #expect(items.first { $0.ref == .meeting(session: "A", key: "a1") }?.meeting == "春季上新计划会")
    }

    @Test func mineIsYoursAndUnclaimed() {
        for o in [nil, "你", "未识别"] { #expect(TodoBoard.isMine(todo("x", owner: o, uid: "x")), "\(o ?? "nil")") }
        for o in ["Mia", "对方"] { #expect(!TodoBoard.isMine(todo("x", owner: o, uid: "x")), "\(o)") }
    }

    @Test func groupsByDueDay() {
        var all = sessions
        var done1 = todo("早做完", uid: "d1"), done2 = todo("很早做完", uid: "d2")
        done1.state = .done; done1.doneAt = today.addingTimeInterval(-10 * 86400)
        done2.state = .done; done2.doneAt = today.addingTimeInterval(-40 * 86400)
        all.append(session("C", "旧会", "2026-10-01", [done1, done2]))
        let groups = TodoBoard.groups(TodoBoard.items(sessions: all, inbox: inbox), today: today, calendar: calendar)
        let keys = groups.map { g in (g.0, g.1.map { $0.item.key }) }
        #expect(keys.map(\.0) == [.overdue, .today, .thisWeek, .later, .noDate, .done])
        #expect(keys.map(\.1) == [["a1"], ["a2"], ["b1"], ["b2"], ["i1"], ["d1"]])
    }

    @Test func starredComeFirstInTheirGroup() {
        var s = sessions
        s[0].notes?.todos = [todo("先说的", t: 10, uid: "x1"), todo("后说的", t: 20, uid: "x2")]
        s[0].notes?.todos[1].starred = true
        let g = TodoBoard.groups(TodoBoard.items(sessions: [s[0]], inbox: []), today: today, calendar: calendar)
        #expect(g.first?.1.map(\.item.key) == ["x2", "x1"])
    }

    @Test func othersAreGroupedByPerson() {
        let s = session("A", "会", "2026-11-20", [todo("a", owner: "Mia", uid: "1"), todo("b", owner: "Ben", uid: "2"), todo("c", owner: "Mia", uid: "3"), todo("d", uid: "4")])
        let others = TodoBoard.byOwner(TodoBoard.items(sessions: [s], inbox: []).filter { !TodoBoard.isMine($0.item) })
        #expect(others.map(\.owner) == ["Ben", "Mia"])
        #expect(others[1].items.count == 2)
    }

    @Test func countsOnlyWhatIsLeft() {
        let c = TodoBoard.counts(TodoBoard.items(sessions: sessions, inbox: inbox), today: today, calendar: calendar)
        #expect(c.open == 5 && c.overdue == 1 && c.dueToday == 1 && c.thisWeek == 2)
    }

    @Test func filtersByWordsMeetingAndOwner() {
        var s = sessions
        s[1].notes?.todos[0].text = "订影棚 B 棚"
        let items = TodoBoard.items(sessions: s, inbox: inbox)
        #expect(TodoBoard.filter(items, meeting: nil, owner: nil, query: "影棚").map(\.item.key) == ["b1"])
        #expect(TodoBoard.filter(items, meeting: "A", owner: nil, query: "").count == 2)
        #expect(TodoBoard.filter(items, meeting: nil, owner: "Mia", query: "").isEmpty)
    }

    @Test func refsAreEqualBySessionAndKey() {
        #expect(TodoRef.meeting(session: "A", key: "k") == .meeting(session: "A", key: "k"))
        #expect(TodoRef.meeting(session: "A", key: "k") != .inbox(key: "k"))
        #expect(Set([TodoRef.inbox(key: "k"), .inbox(key: "k")]).count == 1)
    }
}
