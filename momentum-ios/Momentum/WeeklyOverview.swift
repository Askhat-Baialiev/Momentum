import SwiftUI

/// Progress tab. Shows the week at a glance and surfaces the tasks the student
/// keeps avoiding (Main Task 3), plus local, explainable insights.
struct WeeklyOverviewView: View {
    @EnvironmentObject private var store: FocusStore
    let openTask: (FocusTask) -> Void

    private var week: WeekFocus { Focus.weekFocus(sessions: store.sessions, tasks: store.tasks, containing: Date()) }
    private var insights: [Insight] { Focus.insights(tasks: store.tasks, sessions: store.sessions) }
    private var avoided: [FocusTask] { Focus.avoided(store.tasks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                dailyCard
                avoidedCard
                insightsCard
            }
            .padding(18)
        }
        .background(Style.canvas)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This week").font(.headline)
            HStack {
                metric(Focus.time(week.focusedMinutes), "Focused")
                Spacer(); metric("\(week.totalSessions)", "Sessions")
                Spacer(); metric("\(week.completedBlocks)", "Full blocks")
                Spacer(); metric("\(week.totalDistractions)", "Distractions")
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var dailyCard: some View {
        let maxMinutes = max(25, week.days.map(\.focusedMinutes).max() ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Daily focus").font(.headline)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week.days) { day in
                    VStack(spacing: 6) {
                        Text(day.focusedMinutes > 0 ? "\(day.focusedMinutes)" : "")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        RoundedRectangle(cornerRadius: 5)
                            .fill(day.focusedMinutes > 0 ? Style.focus : Color.secondary.opacity(0.15))
                            .frame(height: max(4, 110 * CGFloat(day.focusedMinutes) / CGFloat(maxMinutes)))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var avoidedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keeps getting postponed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Style.warn)
            if avoided.isEmpty {
                Text("Nothing is being avoided right now.").foregroundStyle(.secondary)
            } else {
                ForEach(avoided.prefix(4)) { task in
                    Button { openTask(task) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(detail(task)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Momentum insights", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Style.focus)
            if insights.isEmpty {
                Text("Run a few sessions and insights will appear here.").foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    insightRow(insight)
                    if insight.id != insights.last?.id { Divider() }
                }
            }
            Text("Insights are generated on your device from your own data. Momentum never changes your plan for you.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func insightRow(_ insight: Insight) -> some View {
        let content = HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol).foregroundStyle(Style.focus).frame(width: 22)
            Text(insight.text).font(.subheadline).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if insight.relatedTaskId != nil { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
        if let id = insight.relatedTaskId, let task = store.task(id) {
            Button { openTask(task) } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private func detail(_ task: FocusTask) -> String {
        let days = Focus.daysUntouched(task)
        if Focus.neverStarted(task) { return "Not started · \(days) day\(days == 1 ? "" : "s") on your list" }
        return "Last worked \(days) day\(days == 1 ? "" : "s") ago"
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
