import Foundation

/// Where a to-do lives: one meeting's notes, or the inbox (手记).
enum TodoRef: Hashable {
    case meeting(session: String, key: String)
    case inbox(key: String)
}

/// A to-do on the board, with the meeting it came from.
struct BoardItem: Identifiable, Equatable {
    let ref: TodoRef
    let item: NoteItem
    /// The meeting's title; nil for the inbox.
    let meeting: String?
    let meetingDate: Date?
    var id: TodoRef { ref }

    var sessionID: String? {
        if case .meeting(let s, _) = ref { return s }
        return nil
    }
}

/// The board's sections under 我的, top to bottom.
enum TodoGroup: CaseIterable {
    case overdue, today, thisWeek, later, noDate, done
}

/// Gathering, grouping and counting every meeting's to-dos (spec › 待办板). Pure: the view and the
/// menu bar row read from it.
enum TodoBoard {
    /// Done ones show for this long.
    static let doneDays = 30

    static func items(sessions: [Session], inbox: [NoteItem]) -> [BoardItem] {
        var out: [BoardItem] = []
        for s in sessions {
            let title = RecordList.listTitle(s)
            for t in s.notes?.todos ?? [] {
                out.append(BoardItem(ref: .meeting(session: s.id, key: t.key), item: t, meeting: title, meetingDate: s.startedAt))
            }
        }
        out += inbox.map { BoardItem(ref: .inbox(key: $0.key), item: $0, meeting: nil, meetingDate: nil) }
        return out
    }

    /// Yours, or no one's (未认领: nil or 未识别). 「对方」 and names are someone else's.
    static func isMine(_ item: NoteItem) -> Bool {
        item.owner == nil || item.owner == "你" || item.owner == "未识别"
    }

    /// Calendar days from today to its due day; nil without one.
    private static func days(_ item: NoteItem, today: Date, calendar: Calendar) -> Int? {
        guard let s = item.due, let d = TodoDue.date(s, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: d)).day
    }

    private static func group(_ item: NoteItem, today: Date, calendar: Calendar) -> TodoGroup? {
        if item.status == .done {
            guard let at = item.doneAt, at >= today.addingTimeInterval(-Double(doneDays) * 86400) else { return nil }
            return .done
        }
        guard let n = days(item, today: today, calendar: calendar), let s = item.due,
              let d = TodoDue.date(s, calendar: calendar) else { return .noDate }
        if n < 0 { return .overdue }
        if n == 0 { return .today }
        return calendar.isDate(d, equalTo: today, toGranularity: .weekOfYear) ? .thisWeek : .later
    }

    /// 星标在前 → 截止日早的在前（没有的在后）→ 新会议在前 → 先说的在前.
    private static func ordered(_ a: BoardItem, _ b: BoardItem) -> Bool {
        if a.item.isStarred != b.item.isStarred { return a.item.isStarred }
        if a.item.due != b.item.due {
            guard let x = a.item.due else { return false }
            guard let y = b.item.due else { return true }
            return x < y
        }
        if a.meetingDate != b.meetingDate {
            guard let x = a.meetingDate else { return false }
            guard let y = b.meetingDate else { return true }
            return x > y
        }
        return (a.item.t ?? .infinity) < (b.item.t ?? .infinity)
    }

    /// Non-empty groups in `TodoGroup` order; done ones only from the last 30 days, newest first.
    static func groups(_ items: [BoardItem], today: Date, calendar: Calendar = .current) -> [(TodoGroup, [BoardItem])] {
        let by = Dictionary(grouping: items) { group($0.item, today: today, calendar: calendar) }
        return TodoGroup.allCases.compactMap { g in
            guard let list = by[g], !list.isEmpty else { return nil }
            if g == .done { return (g, list.sorted { ($0.item.doneAt ?? .distantPast) > ($1.item.doneAt ?? .distantPast) }) }
            return (g, list.sorted(by: ordered))
        }
    }

    /// Someone else's open to-dos, one group per person, by name.
    static func byOwner(_ items: [BoardItem]) -> [(owner: String, items: [BoardItem])] {
        let open = items.filter { $0.item.status != .done }
        let by = Dictionary(grouping: open) { $0.item.ownerShown ?? "" }
        return by.keys.sorted().map { (owner: $0, items: by[$0]!.sorted(by: ordered)) }
    }

    /// Open ones only; `thisWeek` includes today.
    static func counts(_ items: [BoardItem], today: Date, calendar: Calendar = .current)
        -> (open: Int, overdue: Int, dueToday: Int, thisWeek: Int) {
        var c = (open: 0, overdue: 0, dueToday: 0, thisWeek: 0)
        for b in items where b.item.status != .done {
            c.open += 1
            switch group(b.item, today: today, calendar: calendar) {
            case .overdue: c.overdue += 1
            case .today: c.dueToday += 1; c.thisWeek += 1
            case .thisWeek: c.thisWeek += 1
            default: break
            }
        }
        return c
    }

    /// `meeting`: a session id; `owner`: the stored owner; `query`: words in the to-do.
    static func filter(_ items: [BoardItem], meeting: String?, owner: String?, query: String) -> [BoardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items.filter { b in
            (meeting == nil || b.sessionID == meeting)
                && (owner == nil || b.item.owner == owner)
                && (q.isEmpty || b.item.text.localizedCaseInsensitiveContains(q))
        }
    }
}
