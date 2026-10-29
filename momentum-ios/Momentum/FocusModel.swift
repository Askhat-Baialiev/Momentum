import Foundation

// MARK: - Data model

/// A task the student wants to do. The point of Momentum is not to list tasks
/// (other apps do that) but to make it easy to START one. So every task carries
/// a `resistance` (how hard it feels to begin) and an optional tiny `firstStep`.
struct FocusTask: Identifiable, Codable, Equatable, Hashable {
    enum Category: String, Codable, CaseIterable {
        case study, admin, personal
        var label: String {
            switch self { case .study: return "Study"; case .admin: return "Admin"; case .personal: return "Personal" }
        }
        var symbol: String {
            switch self { case .study: return "book"; case .admin: return "tray.full"; case .personal: return "figure.walk" }
        }
    }
    /// How hard it feels to start. This is the student's own feeling, not a priority.
    enum Resistance: Int, Codable, CaseIterable {
        case low = 1, medium = 2, high = 3
        var label: String {
            switch self { case .low: return "Easy to start"; case .medium: return "Some resistance"; case .high: return "Hard to start" }
        }
        var short: String {
            switch self { case .low: return "Low"; case .medium: return "Medium"; case .high: return "High" }
        }
    }

    var id = UUID()
    var title: String
    var category: Category = .study
    var resistance: Resistance = .medium
    /// The tiny two-minute action that gets the task moving.
    var firstStep: String?
    /// Planned number of 25-minute focus blocks.
    var plannedBlocks: Int = 2
    var done: Bool = false
    var createdAt: Date = Date()
    /// Last time any focus session was run on this task.
    var lastWorkedAt: Date?

    init(id: UUID = UUID(), title: String, category: Category = .study, resistance: Resistance = .medium,
         firstStep: String? = nil, plannedBlocks: Int = 2, done: Bool = false,
         createdAt: Date = Date(), lastWorkedAt: Date? = nil) {
        self.id = id; self.title = title; self.category = category; self.resistance = resistance
        self.firstStep = firstStep; self.plannedBlocks = plannedBlocks; self.done = done
        self.createdAt = createdAt; self.lastWorkedAt = lastWorkedAt
    }
}

/// One completed (or partially completed) focus session, logged after the timer.
struct FocusSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var taskId: UUID
    var taskTitle: String
    var start: Date
    var plannedMinutes: Int
    var focusedMinutes: Int
    var finishedFullBlock: Bool
    var distractions: Int

    var dayStart: Date { Calendar.current.startOfDay(for: start) }
}

// MARK: - Weekly summary value types

struct DayFocus: Identifiable, Equatable {
    let date: Date
    let focusedMinutes: Int
    let sessions: Int
    var id: Date { date }
}

struct WeekFocus: Equatable {
    let start: Date
    let end: Date
    let days: [DayFocus]
    let totalSessions: Int
    let totalDistractions: Int
    let completedBlocks: Int
    let plannedBlocks: Int
    var focusedMinutes: Int { days.reduce(0) { $0 + $1.focusedMinutes } }
    var completionRate: Double { plannedBlocks == 0 ? 0 : Double(completedBlocks) / Double(plannedBlocks) }
}

/// An explainable observation generated locally from the student's own data.
struct Insight: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String
    /// Optional task to jump to when the insight is tapped.
    let relatedTaskId: UUID?
}

// MARK: - Pure logic (no UI, unit-testable)

enum Focus {
    /// Length of one focus block in minutes.
    static let block = 25

    static func sameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }

    static func sessions(_ all: [FocusSession], on day: Date) -> [FocusSession] {
        all.filter { sameDay($0.start, day) }.sorted { $0.start < $1.start }
    }

    static func minutesFocused(_ all: [FocusSession], on day: Date) -> Int {
        sessions(all, on: day).reduce(0) { $0 + $1.focusedMinutes }
    }

    /// Consecutive days up to `now` that have at least one session.
    static func streak(_ all: [FocusSession], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let daysWithFocus = Set(all.map { calendar.startOfDay(for: $0.start) })
        var count = 0
        var cursor = calendar.startOfDay(for: now)
        while daysWithFocus.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    /// Whole days since the task was last worked on (nil if never → treated as "since created").
    static func daysUntouched(_ task: FocusTask, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let reference = task.lastWorkedAt ?? task.createdAt
        let from = calendar.startOfDay(for: reference)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    static func neverStarted(_ task: FocusTask) -> Bool { task.lastWorkedAt == nil }

    /// Tasks ranked by how much they are being avoided: never-started and
    /// hard-to-start tasks that have been untouched the longest come first.
    static func avoided(_ tasks: [FocusTask], now: Date = Date()) -> [FocusTask] {
        tasks.filter { !$0.done }
            .map { ($0, avoidanceScore($0, now: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 == $1.1 ? $0.0.createdAt < $1.0.createdAt : $0.1 > $1.1 }
            .map { $0.0 }
    }

    static func avoidanceScore(_ task: FocusTask, now: Date = Date()) -> Int {
        let days = daysUntouched(task, now: now)
        let resistanceWeight = task.resistance.rawValue
        let neverBonus = neverStarted(task) ? 2 : 0
        return days * resistanceWeight + neverBonus
    }

    static func time(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func startOfWeek(containing date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }

    static func weekFocus(sessions all: [FocusSession], tasks: [FocusTask], containing date: Date) -> WeekFocus {
        let calendar = Calendar.current
        let start = startOfWeek(containing: date)
        let endExclusive = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let week = all.filter { $0.start >= start && $0.start < endExclusive }
        let days = (0..<7).compactMap { offset -> DayFocus? in
            guard let d = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayS = week.filter { sameDay($0.start, d) }
            return DayFocus(date: d, focusedMinutes: dayS.reduce(0) { $0 + $1.focusedMinutes }, sessions: dayS.count)
        }
        return WeekFocus(
            start: start,
            end: calendar.date(byAdding: .day, value: 6, to: start) ?? start,
            days: days,
            totalSessions: week.count,
            totalDistractions: week.reduce(0) { $0 + $1.distractions },
            completedBlocks: week.filter { $0.finishedFullBlock }.count,
            plannedBlocks: week.count
        )
    }

    /// Local, explainable insights from the student's own task and session data.
    static func insights(tasks: [FocusTask], sessions all: [FocusSession], now: Date = Date()) -> [Insight] {
        var result: [Insight] = []

        // 1. The task you keep avoiding.
        if let worst = avoided(tasks, now: now).first {
            let days = daysUntouched(worst, now: now)
            if neverStarted(worst) {
                result.append(Insight(symbol: "exclamationmark.triangle",
                                      text: "You have not started “\(worst.title)” yet. It has been on your list for \(days) day\(days == 1 ? "" : "s").",
                                      relatedTaskId: worst.id))
            } else {
                result.append(Insight(symbol: "exclamationmark.triangle",
                                      text: "“\(worst.title)” has not been touched for \(days) day\(days == 1 ? "" : "s").",
                                      relatedTaskId: worst.id))
            }
        }

        let week = weekFocus(sessions: all, tasks: tasks, containing: now)

        // 2. Busiest focus day.
        if let best = week.days.max(by: { $0.focusedMinutes < $1.focusedMinutes }), best.focusedMinutes > 0 {
            let name = best.date.formatted(.dateTime.weekday(.wide))
            result.append(Insight(symbol: "chart.bar.fill",
                                  text: "Your strongest focus day this week was \(name) with \(time(best.focusedMinutes)).",
                                  relatedTaskId: nil))
        }

        // 3. Starting is the hard part: how many sessions survived the first block.
        if week.totalSessions > 0 {
            let full = week.completedBlocks
            result.append(Insight(symbol: "flag.checkered",
                                  text: "You started \(week.totalSessions) focus session\(week.totalSessions == 1 ? "" : "s") this week and finished \(full) full block\(full == 1 ? "" : "s"). The hardest part is starting — you did it \(week.totalSessions) time\(week.totalSessions == 1 ? "" : "s").",
                                  relatedTaskId: nil))
        }

        // 4. Distractions.
        if week.totalDistractions > 0 {
            result.append(Insight(symbol: "bell.slash",
                                  text: "You noted being distracted \(week.totalDistractions) time\(week.totalDistractions == 1 ? "" : "s") but stayed in the session. Noticing it is what keeps you going.",
                                  relatedTaskId: nil))
        }
        return result
    }

    /// A small, fixed library of tiny first steps (the "AI suggestion" assist).
    /// The prototype only needs to work for the expected scenario data, so this
    /// is a lookup rather than a real model, with a safe generic fallback.
    static func suggestedFirstStep(for title: String) -> String {
        let key = title.lowercased()
        if key.contains("report") { return "Open the file and type only the section titles — nothing else." }
        if key.contains("reading") || key.contains("paper") { return "Read just the first page and highlight one sentence." }
        if key.contains("email") || key.contains("reply") { return "Write only the first sentence: “Hi, thank you for…”." }
        if key.contains("slide") || key.contains("present") { return "Make one empty slide with the title on it." }
        if key.contains("gym") || key.contains("run") || key.contains("train") { return "Put on your shoes and fill your water bottle." }
        if key.contains("code") || key.contains("exercise") { return "Open the editor and write the function name and a // TODO." }
        return "Set a 2-minute timer and open the file — that is the whole first step."
    }

    static func validation(_ task: FocusTask) -> String? {
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a task title." }
        if task.plannedBlocks < 1 || task.plannedBlocks > 8 { return "Choose between 1 and 8 focus blocks." }
        return nil
    }
}

// MARK: - Local persistence

struct LocalStoreFile {
    let url: URL
    func load() throws -> StoredData { try JSONDecoder().decode(StoredData.self, from: Data(contentsOf: url)) }
    func save(_ data: StoredData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
    }
}

struct StoredData: Codable, Equatable {
    var tasks: [FocusTask]
    var sessions: [FocusSession]
}
