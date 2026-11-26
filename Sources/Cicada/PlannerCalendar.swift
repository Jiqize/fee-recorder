import Foundation

/// 手帐左页的日历：周一开头的公历，和系统设置无关（样稿是一到日）。纯函数，日期可注入，方便测试。
enum PlannerCalendar {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        c.locale = .current
        return c
    }

    /// 包含 `date` 的那一周，周一到周日 7 天（每天的零点）。
    static func week(containing date: Date, calendar: Calendar = calendar) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 包含 `date` 的那个月的月历：按周排成行，每行 7 格，不属于这个月的格子是 nil。
    static func month(containing date: Date, calendar: Calendar = calendar) -> [[Date?]] {
        guard let range = calendar.dateInterval(of: .month, for: date) else { return [] }
        var rows: [[Date?]] = []
        var day = range.start
        var row: [Date?] = []
        // 第一天前面空几格：周一开头
        let lead = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        row = Array(repeating: nil, count: lead)
        while day < range.end {
            row.append(day)
            if row.count == 7 { rows.append(row); row = [] }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if !row.isEmpty { rows.append(row + Array(repeating: nil, count: 7 - row.count)) }
        return rows
    }

    /// 左页时间线列哪几场：本周（所看那一周）、当月（所看那个月）、更早（所看那个月之前）。
    enum Range: String, CaseIterable { case week, month, earlier }

    static func sessions(_ sessions: [Session], in range: Range, around date: Date, calendar: Calendar = calendar) -> [Session] {
        switch range {
        case .week:
            return sessions.filter { calendar.isDate($0.startedAt, equalTo: date, toGranularity: .weekOfYear) }
        case .month:
            return sessions.filter { calendar.isDate($0.startedAt, equalTo: date, toGranularity: .month) }
        case .earlier:
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            return sessions.filter { $0.startedAt < start }
        }
    }

    /// 有会议的日子（零点），给周历、月历画小点。
    static func meetingDays(_ sessions: [Session], calendar: Calendar = calendar) -> Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// 本周每天到期、还没做完的待办条数（周一到周日），给待办页的七天格。
    static func dueCounts(_ items: [NoteItem], week: [Date], calendar: Calendar = calendar) -> [Int] {
        week.map { day in
            items.filter { item in
                guard item.status != .done, let s = item.due, let d = TodoDue.date(s, calendar: calendar) else { return false }
                return calendar.isDate(d, inSameDayAs: day)
            }.count
        }
    }

    /// 按月分组（「更早」和搜索结果用），新的在前；组标题是「2026年10月」这样的月份。
    static func byMonth(_ sessions: [Session], calendar: Calendar = calendar) -> [(title: String, sessions: [Session])] {
        var out: [(title: String, sessions: [Session])] = []
        for s in sessions {
            let title = dateText(s.startedAt, "yMMMM")
            if out.last?.title == title { out[out.count - 1].sessions.append(s) } else { out.append((title, [s])) }
        }
        return out
    }

    /// 本周小结：几场、一共多少分钟、说得最多的人（只算有名字的说话人；没有就 nil）。
    static func summary(_ sessions: [Session]) -> (count: Int, minutes: Int, talker: String?) {
        var seconds = 0.0
        var talk: [String: Int] = [:]
        for s in sessions {
            if let end = s.endedAt { seconds += max(0, end.timeIntervalSince(s.startedAt)) }
            else if let last = s.lines.last { seconds += last.t }
            let numbers = SpeakerLabels.numbers(s)
            let names = SpeakerLabels.names(s)
            for l in s.lines where l.speaker == "them" {
                if let n = numbers[l.id], let name = names[n], !name.isEmpty { talk[name, default: 0] += 1 }
            }
        }
        let top = talk.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
        return (sessions.count, Int((seconds / 60).rounded()), top)
    }

    /// 每天开了几场（零点 → 场数），给月历按忙闲填色。
    static func meetingCounts(_ sessions: [Session], calendar: Calendar = calendar) -> [Date: Int] {
        var out: [Date: Int] = [:]
        for s in sessions { out[calendar.startOfDay(for: s.startedAt), default: 0] += 1 }
        return out
    }

    /// 按周分组（月页用），新的在前；组号是公历第几周（周一开头）。
    static func byWeek(_ sessions: [Session], calendar: Calendar = calendar) -> [(week: Int, sessions: [Session])] {
        var out: [(week: Int, sessions: [Session])] = []
        for s in sessions {
            let w = calendar.component(.weekOfYear, from: s.startedAt)
            if out.last?.week == w { out[out.count - 1].sessions.append(s) } else { out.append((w, [s])) }
        }
        return out
    }
}
