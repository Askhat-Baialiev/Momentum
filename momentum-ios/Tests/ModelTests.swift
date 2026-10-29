// Pure-logic checks for the Momentum model. No UI, no XCTest — this file is
// concatenated with FocusModel.swift and run through the Swift interpreter by
// test-model.sh, so it uses plain assert() and runs top to bottom.

import Foundation

func check(_ condition: Bool, _ label: String) {
    if condition { print("  ok  · \(label)") }
    else { print("  FAIL· \(label)"); exit(1) }
}

let cal = Calendar.current
let now = cal.date(from: DateComponents(year: 2025, month: 11, day: 12, hour: 10))!  // a Wednesday
func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

print("Momentum model checks")

// 1. daysUntouched counts whole days from last worked / created.
let t1 = FocusTask(title: "HCI report", resistance: .high, createdAt: daysAgo(4), lastWorkedAt: nil)
check(Focus.daysUntouched(t1, now: now) == 4, "untouched never-started task counts days since created")
check(Focus.neverStarted(t1), "never started detected")

let t2 = FocusTask(title: "Readings", resistance: .medium, createdAt: daysAgo(5), lastWorkedAt: daysAgo(2))
check(Focus.daysUntouched(t2, now: now) == 2, "untouched counts days since last worked")

// 2. avoidance ranking: hard + never-started + old ranks first.
let email = FocusTask(title: "Reply to email", resistance: .medium, createdAt: daysAgo(2), lastWorkedAt: nil)
let gym = FocusTask(title: "Gym", resistance: .low, createdAt: daysAgo(3), lastWorkedAt: daysAgo(1))
let ranked = Focus.avoided([t1, t2, email, gym], now: now)
check(ranked.first?.title == "HCI report", "most avoided task is surfaced first")
check(ranked.last?.title == "Gym", "low-resistance recent task ranks last")

// 3. suggested first steps are task-aware with a safe fallback.
check(Focus.suggestedFirstStep(for: "HCI report").contains("section titles"), "report suggestion")
check(Focus.suggestedFirstStep(for: "Reply to internship email").contains("first sentence"), "email suggestion")
check(!Focus.suggestedFirstStep(for: "Something unknown").isEmpty, "generic fallback is never empty")

// 4. streak counts consecutive days ending today.
let sToday = FocusSession(taskId: t2.id, taskTitle: t2.title, start: now, plannedMinutes: 25, focusedMinutes: 25, finishedFullBlock: true, distractions: 0)
let sYesterday = FocusSession(taskId: t2.id, taskTitle: t2.title, start: daysAgo(1), plannedMinutes: 25, focusedMinutes: 20, finishedFullBlock: false, distractions: 1)
let sGap = FocusSession(taskId: t2.id, taskTitle: t2.title, start: daysAgo(3), plannedMinutes: 25, focusedMinutes: 25, finishedFullBlock: true, distractions: 0)
check(Focus.streak([sToday, sYesterday, sGap], now: now) == 2, "streak stops at the first missing day")
check(Focus.streak([sGap], now: now) == 0, "no streak when today has no session")

// 5. weekly aggregation sums focus and counts full blocks / distractions.
let week = Focus.weekFocus(sessions: [sToday, sYesterday], tasks: [t1, t2], containing: now)
check(week.focusedMinutes == 45, "weekly focused minutes summed (25 + 20)")
check(week.totalSessions == 2, "weekly session count")
check(week.completedBlocks == 1, "weekly full blocks counted")
check(week.totalDistractions == 1, "weekly distractions counted")

// 6. validation guards empty titles and silly block counts.
check(Focus.validation(FocusTask(title: "   ")) != nil, "empty title rejected")
check(Focus.validation(FocusTask(title: "Essay", plannedBlocks: 0)) != nil, "zero blocks rejected")
check(Focus.validation(FocusTask(title: "Essay", plannedBlocks: 2)) == nil, "valid task accepted")

// 7. JSON round-trip (local persistence shape).
let data = StoredData(tasks: [t1, t2], sessions: [sToday])
let encoded = try! JSONEncoder().encode(data)
let decoded = try! JSONDecoder().decode(StoredData.self, from: encoded)
check(decoded == data, "StoredData survives JSON round-trip")

print("All model checks passed.")
