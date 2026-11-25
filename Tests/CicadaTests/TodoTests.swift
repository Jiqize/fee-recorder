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

/// AI 重写纪要时：动过的、自己加的、删掉的都按用户的来。
@Suite struct TodoMergeTests {
    private let day = Date(timeIntervalSince1970: 1_795_600_000)

    private func ai(_ text: String, t: Double? = nil, owner: String? = nil, uid: String? = nil) -> NoteItem {
        NoteItem(text: text, owner: owner, support: 1, t: t, uid: uid)
    }

    private func notes(_ todos: [NoteItem], removed: [TodoTombstone]? = nil) -> MeetingNotes {
        var n = MeetingNotes()
        n.todos = todos
        n.removedTodos = removed
        return n
    }

    @Test func touchedStayUntouchedFollowTheReplyAndNewOnesJoin() {
        let latest = notes([ai("A", uid: "a0000001"), ai("B", uid: "b0000001")])
            .changingTodo(key: "a0000001", .state(.done), now: day)
        var reply = notes([ai("A"), ai("B", t: 30), ai("C")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["A", "B", "C"])
        #expect(reply.todos[0].status == .done && reply.todos[0].uid == "a0000001")
        #expect(reply.todos[1].uid == "b0000001", "an untouched one keeps its id")
        #expect(reply.todos.allSatisfy { $0.uid != nil })
    }

    @Test func untouchedKeepTheEarlierTime() {
        let latest = notes([ai("B", t: 20, uid: "b0000001")])
        var reply = notes([ai("B", t: 30)])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos[0].t == 20)
    }

    @Test func anEditedTodoIsNotAddedBackInTheAIWording() {
        let latest = notes([ai("A", uid: "a0000001")]).changingTodo(key: "a0000001", .text("A2"), now: day)
        var reply = notes([ai("A")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["A2"])
    }

    @Test func deletedStayDeleted() {
        let latest = notes([], removed: [TodoTombstone(text: "X", t: nil, owner: nil)])
        var reply = notes([ai("X"), ai("Z")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["Z"])
        #expect(reply.removedTodos?.map(\.text) == ["X"], "the tombstone carries on")
    }

    @Test func yourOwnStayWhenTheReplyLeavesThemOut() {
        let latest = notes([ai("A", uid: "a0000001")]).addingTodo(text: "U", owner: nil, due: nil)
        var reply = notes([ai("A")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["U", "A"], "kept ones first")
    }

    @Test func keptFromARetranscribeComeBack() {
        let k = notes([ai("K", uid: "k0000001")]).changingTodo(key: "k0000001", .state(.done), now: day).todos[0]
        var reply = notes([ai("K"), ai("Y")])
        TodoMerge.carry(from: nil, kept: KeptTodos(items: [k], removed: [TodoTombstone(text: "Y", t: nil, owner: nil)]), into: &reply)
        #expect(reply.todos.map(\.text) == ["K"])
        #expect(reply.todos[0].status == .done)
        #expect(reply.removedTodos?.map(\.text) == ["Y"])
    }

    @Test func rewordedIsTheSameWhenSaidAtTheSameMomentByTheSameOwner() {
        let latest = notes([ai("下周三前改尺码表", t: 80, owner: "你", uid: "a0000001")])
            .changingTodo(key: "a0000001", .state(.done), now: day)
        for wording in ["周三前完成尺码表改版", "Redo the size guide by Wednesday"] {
            var reply = notes([ai(wording, t: 80, owner: "你")])
            TodoMerge.carry(from: latest, into: &reply)
            #expect(reply.todos.map(\.text) == ["下周三前改尺码表"], "\(wording)")
            #expect(reply.todos[0].status == .done)
        }
    }

    @Test func aRewordedTombstoneStillBuries() {
        let latest = notes([], removed: [TodoTombstone(text: "X", t: 104, owner: "Mia")])
        var reply = notes([ai("另一种说法", t: 104.5, owner: "Mia")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.isEmpty)
    }

    /// 保留的 A 已按文字认到回复里的 A，同一时刻别人的 B 不能再被它按时刻吞掉。
    @Test func sameMomentDifferentOwnerIsAnotherTodo() {
        let latest = notes([ai("A", t: 80, owner: "你", uid: "a0000001")]).changingTodo(key: "a0000001", .state(.done), now: day)
        var reply = notes([ai("A", t: 80, owner: "你"), ai("B", t: 80, owner: "Ben")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["A", "B"])
    }

    /// 同一句话里说的两件事：出处时间、负责人都一样。勾了一件不能把另一件也吞掉。
    @Test func tickingOneOfTwoFromTheSameSentenceKeepsTheOther() {
        let latest = notes([ai("A", t: 80, owner: "你", uid: "a0000001"), ai("B", t: 80, owner: "你", uid: "b0000001")])
            .changingTodo(key: "a0000001", .state(.done), now: day)
        var reply = notes([ai("A", t: 80, owner: "你"), ai("B", t: 80, owner: "你")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["A", "B"])
        #expect(reply.todos[1].uid == "b0000001")
    }

    @Test func deletingOneOfTwoFromTheSameSentenceKeepsTheOther() {
        let latest = notes([ai("B", t: 80, owner: "你", uid: "b0000001")], removed: [TodoTombstone(text: "A", t: 80, owner: "你")])
        var reply = notes([ai("A", t: 80, owner: "你"), ai("B", t: 80, owner: "你")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["B"])
    }

    /// 模型常把旧待办原样抄回来却不带 due：没动过的也留住原来的截止日。
    @Test func anEchoWithoutADueDateKeepsTheOldOne() {
        var old = ai("B", t: 20, uid: "b0000001")
        old.due = "2026-11-27"
        var reply = notes([ai("B")])
        TodoMerge.carry(from: notes([old]), into: &reply)
        #expect(reply.todos[0].due == "2026-11-27")
    }

    /// 放宽（2026-11-25）：那一刻两边都只有一条时，负责人变了也是同一件事。
    @Test func theOnlyCandidateAtAMomentMatchesEvenWithANewOwner() {
        let latest = notes([ai("设计确认签署", t: 52, uid: "a0000001")]).changingTodo(key: "a0000001", .state(.done), now: day)
        var reply = notes([ai("设计团队完成审批", t: 52, owner: "对方")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["设计确认签署"])
        #expect(reply.todos[0].status == .done)
    }

    @Test func twoCandidatesAtAMomentStillGoByOwner() {
        let latest = notes([ai("A", t: 80, owner: "你", uid: "a0000001")]).changingTodo(key: "a0000001", .state(.done), now: day)
        var reply = notes([ai("B", t: 80, owner: "Ben"), ai("C", t: 80, owner: "Mia")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.map(\.text) == ["A", "B", "C"])
    }

    @Test func theOnlyCandidateAtATombstonesMomentIsBuriedEvenWithANewOwner() {
        let latest = notes([], removed: [TodoTombstone(text: "订影棚", t: 104, owner: nil)])
        var reply = notes([ai("Mia books the studio", t: 104, owner: "Mia")])
        TodoMerge.carry(from: latest, into: &reply)
        #expect(reply.todos.isEmpty)
    }

    @Test func sameComparesTextIgnoringCaseAndSpaces() {
        #expect(TodoMerge.same(ai(" Ship it "), ai("ship it")))
        #expect(!TodoMerge.same(ai("A", t: 10), ai("B", t: 12)))
        #expect(TodoMerge.buried(ai("x"), in: [TodoTombstone(text: "X ", t: nil, owner: nil)]))
    }

    /// 存的是「说话人2」，改名后模型拿到的是「Ben」：比较时按现在的名字看，存的保持原样。
    @Test func aRenamedSpeakerStillMatchesTouchedAndDeleted() {
        var latest = notes([ai("说话人2 发样衣", t: 52, owner: "说话人2", uid: "a0000001")])
            .changingTodo(key: "a0000001", .state(.done), now: day)
        latest.removedTodos = [TodoTombstone(text: "说话人2 订影棚", t: 104, owner: "说话人2")]
        var reply = notes([ai("Ben sends the samples", t: 52, owner: "Ben"), ai("Ben books the studio", t: 104, owner: "Ben")])
        TodoMerge.carry(from: latest, names: [2: "Ben"], into: &reply)
        #expect(reply.todos.map(\.text) == ["说话人2 发样衣"])
        #expect(reply.todos[0].owner == "说话人2", "stored as it was")
        #expect(reply.removedTodos?.first?.owner == "说话人2")
    }

    @Test func renamingASpeakerAlsoRenamesTheAIWordingAndTombstones() {
        var n = notes([ai("A", uid: "a0000001")]).changingTodo(key: "a0000001", .text("给说话人2 发表格"), now: day)
        n.todos[0].aiText = "说话人2 发表格"
        n.removedTodos = [TodoTombstone(text: "说话人2 跟进", t: 5, owner: "说话人2")]
        let shown = SpeakerLabels.named(n, [2: "Ben"])
        #expect(shown.todos[0].aiText == "Ben 发表格")
        #expect(shown.removedTodos == [TodoTombstone(text: "Ben 跟进", t: 5, owner: "Ben")])
    }
}

/// 重新转写前留下动过的待办，转写完的纪要再带回来。
@MainActor @Suite struct TodoKeptTests {
    @Test func retranscribingKeepsTouchedTodosAndTombstones() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-todo-\(UUID().uuidString)")
        let store = SessionStore(root: root)
        let s = store.beginImport(file: URL(fileURLWithPath: "/tmp/a.m4a"), recordedAt: Date(), duration: 60)
        var n = MeetingNotes()
        n.summary = "s"
        n.todos = [NoteItem(text: "A", owner: nil, support: 1, uid: "a0000001"), NoteItem(text: "B", owner: nil, support: 1, uid: "b0000001"),
                   NoteItem(text: "C", owner: nil, support: 1, uid: "c0000001")]
        n = n.changingTodo(key: "a0000001", .state(.done), now: Date()).changingTodo(key: "c0000001", .delete, now: Date())
        store.setNotes(s.id, n)
        store.restartImport(s.id)
        let kept = store.session(s.id)?.keptTodos
        #expect(store.session(s.id)?.notes == nil)
        #expect(kept?.items.map(\.text) == ["A"])
        #expect(kept?.removed.map(\.text) == ["C"])
        store.setKeptTodos(s.id, nil)
        #expect(store.session(s.id)?.keptTodos == nil)
    }
}

/// 截止日：存成 yyyy-MM-dd，显示按今天算。
@MainActor @Suite struct TodoDueTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }
    private func d(_ s: String) -> Date { TodoDue.date(s, calendar: calendar)! }

    @Test func readsAndWritesDays() {
        #expect(TodoDue.date("2026-11-25") != nil)
        #expect(TodoDue.date("下周三") == nil)
        #expect(TodoDue.date("2026-13-40") == nil)
        #expect(TodoDue.string(TodoDue.date("2026-11-25")!) == "2026-11-25")
    }

    @Test func labelsCountFromToday() {
        let today = d("2026-11-25").addingTimeInterval(15 * 3600)   // 周三下午
        func label(_ s: String) -> (text: String, overdue: Bool) { TodoDue.label(s, today: today, calendar: calendar) }
        #expect(label("2026-11-25").text == L("今天") && !label("2026-11-25").overdue)
        #expect(label("2026-11-26").text == L("明天"))
        #expect(label("2026-11-28").text == dateText(d("2026-11-28"), "EEE"))
        #expect(label("2026-12-06").text == dateText(d("2026-12-06"), "MMMd"))
        #expect(label("2026-11-23").text == L("逾期 \(2) 天") && label("2026-11-23").overdue)
    }

    @Test func thePromptSaysTheMeetingDate() {
        let line = TranscriptLine(id: "l1", t: 3, speaker: "me", src: "下周三前给大家看", dst: "", srcLang: "zh-Hans", dstLang: "en")
        let p = NotesEngine.prompt(notes: MeetingNotes(), lines: [line], from: 0, language: "Simplified Chinese", final: true,
                                   meetingDate: d("2026-11-20").addingTimeInterval(10 * 3600))
        #expect(p.contains("The meeting date is 2026-11-20 (Friday)."))
        #expect(p.contains("\"due\""))
        let q = NotesEngine.prompt(notes: MeetingNotes(), lines: [line], from: 0, language: "Simplified Chinese", final: true)
        #expect(!q.contains("The meeting date"))
    }

    @Test func parsesOnlyRealDatesFromTheMeetingDayOn() {
        func due(_ v: String, meeting: Date? = nil) -> String? {
            let raw = #"{"summary":"s","topics":[{"title":"t","points":[]}],"todos":[{"text":"a","due":"\#(v)","evidence":["L1"]}]}"#
            return NotesEngine.parse(raw, times: [3], startedAt: 0, meetingDate: meeting)?.todos.first?.due
        }
        #expect(due("2026-11-25") == "2026-11-25")
        #expect(due("next week") == nil)
        #expect(due("2026-11-19", meeting: d("2026-11-20").addingTimeInterval(10 * 3600)) == nil)
        #expect(due("2026-11-20", meeting: d("2026-11-20").addingTimeInterval(10 * 3600)) == "2026-11-20")
    }
}
