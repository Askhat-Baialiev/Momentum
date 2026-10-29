import Foundation
import SwiftUI

/// Single source of truth for the prototype. Holds tasks and logged sessions,
/// persists them locally as JSON, and exposes a small undo snackbar.
final class FocusStore: ObservableObject {
    @Published private(set) var tasks: [FocusTask] = []
    @Published private(set) var sessions: [FocusSession] = []
    @Published var undoMessage: String?

    private let file = LocalStoreFile(
        url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("momentum-store.json"))
    private var undoSnapshot: StoredData?
    private var undoClearItem: DispatchWorkItem?

    init() {
        if let loaded = try? file.load(), !loaded.tasks.isEmpty {
            tasks = loaded.tasks; sessions = loaded.sessions
        } else {
            let seed = FocusStore.sample()
            tasks = seed.tasks; sessions = seed.sessions
            persist()
        }
    }

    // MARK: Derived

    var activeTasks: [FocusTask] { tasks.filter { !$0.done } }
    var doneTasks: [FocusTask] { tasks.filter { $0.done } }
    func task(_ id: UUID) -> FocusTask? { tasks.first { $0.id == id } }
    func sessions(for task: FocusTask) -> [FocusSession] {
        sessions.filter { $0.taskId == task.id }.sorted { $0.start > $1.start }
    }

    // MARK: Tasks

    func commit(_ task: FocusTask) {
        snapshot()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        persist()
    }

    func toggleDone(_ task: FocusTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        snapshot()
        tasks[index].done.toggle()
        persist()
        flash(tasks[index].done ? "Task completed" : "Task reopened")
    }

    func remove(_ task: FocusTask) {
        snapshot()
        tasks.removeAll { $0.id == task.id }
        persist()
        flash("Task removed")
    }

    func setFirstStep(_ step: String, for task: FocusTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].firstStep = step
        persist()
    }

    // MARK: Sessions

    /// Log a finished focus session and stamp the task as worked-on today.
    func logSession(task: FocusTask, plannedMinutes: Int, focusedMinutes: Int, distractions: Int, now: Date = Date()) {
        snapshot()
        let session = FocusSession(
            taskId: task.id, taskTitle: task.title, start: now,
            plannedMinutes: plannedMinutes, focusedMinutes: focusedMinutes,
            finishedFullBlock: focusedMinutes >= plannedMinutes, distractions: distractions)
        sessions.append(session)
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index].lastWorkedAt = now }
        persist()
        flash("Focus session saved · \(Focus.time(focusedMinutes))")
    }

    func removeSession(_ session: FocusSession) {
        snapshot()
        sessions.removeAll { $0.id == session.id }
        persist()
        flash("Session removed")
    }

    // MARK: Undo + reset

    func undo() {
        guard let snap = undoSnapshot else { return }
        tasks = snap.tasks; sessions = snap.sessions
        undoSnapshot = nil; undoMessage = nil
        persist()
    }

    func reset() {
        let seed = FocusStore.sample()
        tasks = seed.tasks; sessions = seed.sessions
        undoSnapshot = nil; undoMessage = nil
        persist()
    }

    // MARK: Internals

    private func snapshot() { undoSnapshot = StoredData(tasks: tasks, sessions: sessions) }
    private func persist() { try? file.save(StoredData(tasks: tasks, sessions: sessions)) }

    private func flash(_ message: String) {
        undoMessage = message
        undoClearItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.undoMessage = nil }
        undoClearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    // MARK: Sample day (scenario: "Alice")

    /// Expected data for the user test. Alice has been avoiding the HCI report
    /// (never started, 4 days old) and has a few sessions earlier this week.
    static func sample(now: Date = Date()) -> StoredData {
        let calendar = Calendar.current
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now) ?? now }

        let report = FocusTask(title: "HCI report", category: .study, resistance: .high,
                               firstStep: nil, plannedBlocks: 3, createdAt: daysAgo(4), lastWorkedAt: nil)
        let readings = FocusTask(title: "Readings for Interaction Design", category: .study, resistance: .medium,
                                 firstStep: "Read just the first page and highlight one sentence.",
                                 plannedBlocks: 2, createdAt: daysAgo(3), lastWorkedAt: daysAgo(2))
        let email = FocusTask(title: "Reply to internship email", category: .admin, resistance: .medium,
                              firstStep: nil, plannedBlocks: 1, createdAt: daysAgo(2), lastWorkedAt: nil)
        let gym = FocusTask(title: "Gym", category: .personal, resistance: .low,
                            firstStep: "Put on your shoes and fill your water bottle.",
                            plannedBlocks: 1, createdAt: daysAgo(3), lastWorkedAt: daysAgo(1))

        let sessions: [FocusSession] = [
            FocusSession(taskId: readings.id, taskTitle: readings.title, start: daysAgo(2),
                         plannedMinutes: 25, focusedMinutes: 25, finishedFullBlock: true, distractions: 1),
            FocusSession(taskId: readings.id, taskTitle: readings.title, start: daysAgo(2),
                         plannedMinutes: 25, focusedMinutes: 18, finishedFullBlock: false, distractions: 2),
            FocusSession(taskId: gym.id, taskTitle: gym.title, start: daysAgo(1),
                         plannedMinutes: 25, focusedMinutes: 25, finishedFullBlock: true, distractions: 0)
        ]
        return StoredData(tasks: [report, readings, email, gym], sessions: sessions)
    }
}
