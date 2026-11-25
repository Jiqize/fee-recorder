import Foundation
import Testing
@testable import Cicada

/// 手帐左页：周一开头的周、月历、按范围挑会议、七天到期条数。
@Suite struct PlannerCalendarTests {
    private var cal: Calendar {
        var c = PlannerCalendar.calendar
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func day(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s.count == 10 ? s + " 00:00" : s)!
    }

    private func session(_ id: String, _ at: String) -> Session {
        Session(id: id, title: id, startedAt: day(at), endedAt: nil, lines: [], hasAudio: false)
    }

    @Test func weekStartsOnMondayWhateverTheSystemSays() {
        // 2026-11-20 是周五；系统哪怕是周日开头，也排成 16（一）… 22（日）
        let w = PlannerCalendar.week(containing: day("2026-11-20 10:00"), calendar: cal)
        #expect(w.count == 7)
        #expect(w.first == day("2026-11-16"))
        #expect(w.last == day("2026-11-22"))
        // 周日那天还在同一周
        #expect(PlannerCalendar.week(containing: day("2026-11-22 23:00"), calendar: cal).first == day("2026-11-16"))
    }

    @Test func monthGridPadsToMonday() {
        // 2026 年 11 月 1 日是周日：第一行前面空 6 格
        let m = PlannerCalendar.month(containing: day("2026-11-20"), calendar: cal)
        #expect(m.first?.prefix(6).allSatisfy { $0 == nil } == true)
        #expect(m.first?[6] == day("2026-11-01"))
        #expect(m.allSatisfy { $0.count == 7 })
        #expect(m.flatMap { $0 }.compactMap { $0 }.count == 30)
    }

    @Test func rangesPickTheirMeetings() {
        let all = [session("a", "2026-11-20 10:00"), session("b", "2026-11-18 15:30"),
                   session("c", "2026-11-09 09:00"), session("d", "2026-10-30 09:00")]
        let at = day("2026-11-20 12:00")
        #expect(PlannerCalendar.sessions(all, in: .week, around: at, calendar: cal).map(\.id) == ["a", "b"])
        #expect(PlannerCalendar.sessions(all, in: .month, around: at, calendar: cal).map(\.id) == ["a", "b", "c"])
        #expect(PlannerCalendar.sessions(all, in: .earlier, around: at, calendar: cal).map(\.id) == ["d"])
        #expect(PlannerCalendar.meetingDays(all, calendar: cal).contains(day("2026-11-18")))
    }

    @Test func weekSummaryCountsMinutesAndTopTalker() {
        var a = session("a", "2026-11-20 10:00")
        a.endedAt = a.startedAt.addingTimeInterval(32 * 60)
        var b = session("b", "2026-11-18 15:30")
        b.endedAt = b.startedAt.addingTimeInterval(25 * 60)
        let s = PlannerCalendar.summary([a, b])
        #expect(s.count == 2)
        #expect(s.minutes == 57)
        #expect(s.talker == nil)
    }

    @Test func dueCountsSkipDoneAndUndated() {
        let week = PlannerCalendar.week(containing: day("2026-11-25"), calendar: cal)
        var done = NoteItem(text: "做完的", owner: "你", support: 1, uid: "3", due: "2026-11-25")
        done.state = .done
        let items = [NoteItem(text: "改尺码表", owner: "你", support: 1, uid: "1", due: "2026-11-25"),
                     NoteItem(text: "色卡", owner: "你", support: 1, uid: "2", due: "2026-11-23"),
                     done, NoteItem(text: "没日子", owner: "你", support: 1, uid: "4")]
        #expect(PlannerCalendar.dueCounts(items, week: week, calendar: cal) == [1, 0, 1, 0, 0, 0, 0])
    }
}

/// 分隔页、笔身的竖排字：中文逐字竖写，⌘R、英文词整体横躺。
@Suite struct VerticalLabelTests {
    @Test func chineseStandsAndShortcutLiesDown() {
        let r = VerticalLabel.runs("开始听 ⌘R")
        #expect(r.map(\.text) == ["开", "始", "听", "⌘R"])
        #expect(r.map(\.upright) == [true, true, true, false])
    }

    @Test func latinOnlyIsOneRun() {
        #expect(VerticalLabel.runs("This Week").allSatisfy { !$0.upright })
        #expect(VerticalLabel.runs("待办").count == 2)
    }
}
