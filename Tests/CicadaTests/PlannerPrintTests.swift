import Foundation
import Testing
@testable import Cicada

@Suite struct PlannerPrintTests {
    private func session(todos: Int, summary: String = "确定春季上新以亚麻系列为主推。") -> Session {
        var n = MeetingNotes()
        n.summary = summary
        n.topics = [NoteTopic(start: 0, title: "拍摄排期", summary: "", points: ["样衣 3 月 3 日到货"])]
        n.conclusions = [NoteItem(text: "拍摄定在 3 月 6 日", owner: nil, support: 1)]
        n.todos = (0..<todos).map { NoteItem(text: "第 \($0 + 1) 件要做的事", owner: "你", support: 1, uid: "t\($0)") }
        return Session(id: "p", title: "春季上新计划会", startedAt: Date(timeIntervalSince1970: 0),
                       endedAt: Date(timeIntervalSince1970: 1920), lines: [], hasAudio: false, notes: n, renamed: true)
    }

    @Test func shortMeetingFitsOnePage() {
        let pages = PlannerPrint.paginate(session(todos: 2), paper: .a5)
        #expect(pages.count == 1)
        #expect(pages[0].rows.first?.kind == .title)
        #expect(pages[0].rows.filter { $0.kind == .todo }.count == 2)
    }

    @Test func manyTodosFlowOntoMorePagesStably() {
        let s = session(todos: 60)
        let pages = PlannerPrint.paginate(s, paper: .a5)
        #expect(pages.count > 1)
        #expect(PlannerPrint.paginate(s, paper: .a5) == pages)
        // 每个待办正好印一次，每页不超过横线行数，页码对得上
        #expect(pages.flatMap(\.rows).filter { $0.kind == .todo }.count == 60)
        let cap = PlannerPrint.rowsPerPage(.a5)
        for (i, p) in pages.enumerated() {
            #expect(p.rows.reduce(0) { $0 + $1.span } <= cap)
            #expect(p.number == i + 1 && p.count == pages.count)
            #expect(p.rows.first?.kind != .blank && p.rows.last?.kind != .blank)
            #expect((p.stampRow != nil) == (p.number == p.count))
        }
        // A4 一页行数更多，页数不会更多
        #expect(PlannerPrint.paginate(s, paper: .a4).count <= pages.count)
    }

    @Test func sectionHeadStaysWithItsFirstItem() {
        for todos in 1...40 {
            for p in PlannerPrint.paginate(session(todos: todos), paper: .a5) {
                #expect(p.rows.last?.kind != .head)
            }
        }
    }

    @Test func longSummaryContinuesOnNextPage() {
        let long = String(repeating: "这是一段很长的摘要，用来检查摘要能一行一行续到下一页。", count: 40)
        let pages = PlannerPrint.paginate(session(todos: 1, summary: long), paper: .a5)
        #expect(pages.count > 1)
        #expect(pages[0].rows.contains { $0.kind == .text } && pages[1].rows.contains { $0.kind == .text })
    }

    @Test func paperSetting() {
        #expect(PrintPaper.a5.size == CGSize(width: 420, height: 595))
        #expect(PrintPaper.a4.size == CGSize(width: 595, height: 842))
        #expect(PrintPaper(rawValue: "a4") == .a4)
    }
}
