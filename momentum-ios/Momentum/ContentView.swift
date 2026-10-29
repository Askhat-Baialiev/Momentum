import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FocusStore
    @State private var selectedTab = 0

    // Sheets (modal interactions, like Planora): focus flow, edit task, task actions.
    @State private var startingSession = false
    @State private var sessionTask: FocusTask?        // preselected task for the focus flow (nil = choose)
    @State private var editing: FocusTask?
    @State private var actionsFor: FocusTask?
    @State private var showReset = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    startGeneric: { sessionTask = nil; startingSession = true },
                    startTask: { sessionTask = $0; startingSession = true },
                    openActions: { actionsFor = $0 },
                    openTasks: { selectedTab = 1 })
                .navigationTitle("Today")
                .toolbar { toolbar }
            }
            .tabItem { Label("Today", systemImage: "bolt.fill") }.tag(0)

            NavigationStack {
                TasksView(startTask: { sessionTask = $0; startingSession = true },
                          openActions: { actionsFor = $0 })
                .navigationTitle("Tasks")
                .toolbar { toolbar }
            }
            .tabItem { Label("Tasks", systemImage: "checklist") }.tag(1)

            NavigationStack {
                WeeklyOverviewView(openTask: { task in actionsFor = task })
                    .navigationTitle("Progress")
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }.tag(2)
        }
        .safeAreaInset(edge: .bottom) {
            if let message = store.undoMessage {
                HStack { Text(message); Spacer(); Button("Undo") { store.undo() }.bold() }
                    .padding().background(.regularMaterial)
            }
        }
        // Modal: the focus session (several views, ends back at the root).
        .sheet(isPresented: $startingSession) {
            FocusSessionFlow(preselected: sessionTask)
                .environmentObject(store)
                .presentationBackground(Style.canvas)
        }
        // Modal: add / edit a task.
        .sheet(item: $editing) { task in
            TaskEditor(task: task).environmentObject(store).presentationBackground(Style.canvas)
        }
        // Modal: quick actions for a task (medium sheet).
        .sheet(item: $actionsFor) { task in
            TaskActionsView(task: task,
                            start: { actionsFor = nil; sessionTask = $0; startingSession = true },
                            edit: { actionsFor = nil; editing = $0 })
            .environmentObject(store)
            .presentationDetents([.medium])
            .presentationBackground(Style.canvas)
        }
        .confirmationDialog("Reset to the sample day?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Reset sample day", role: .destructive) { store.reset(); selectedTab = 0 }
        } message: { Text("This replaces your current tasks and sessions.") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Reset sample day", systemImage: "arrow.counterclockwise") { showReset = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { editing = FocusTask(title: "") } label: { Label("Add task", systemImage: "plus") }
        }
    }
}

// MARK: - Today (home / root view)

struct TodayView: View {
    @EnvironmentObject private var store: FocusStore
    let startGeneric: () -> Void
    let startTask: (FocusTask) -> Void
    let openActions: (FocusTask) -> Void
    let openTasks: () -> Void

    private var todaysSessions: [FocusSession] { Focus.sessions(store.sessions, on: Date()) }
    private var avoided: [FocusTask] { Focus.avoided(store.tasks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsCard
                startCard
                avoidedCard
                todayCard
            }
            .padding(18)
        }
        .background(Style.canvas)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hi Alice").font(.largeTitle.bold())
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statsCard: some View {
        HStack {
            metric("\(Focus.streak(store.sessions))", "Day streak", "flame.fill", Style.warn)
            Spacer()
            metric(Focus.time(Focus.minutesFocused(store.sessions, on: Date())), "Focused today", "bolt.fill", Style.focus)
            Spacer()
            metric("\(todaysSessions.count)", "Sessions", "checkmark.circle.fill", Style.good)
        }
        .padding(18)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var startCard: some View {
        Button(action: startGeneric) {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a focus session").font(.headline)
                    Text("Pick a task, take the first small step").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Style.focus, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var avoidedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What you keep putting off", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Style.warn)
            if avoided.isEmpty {
                Text("Nothing is piling up. Nice.").foregroundStyle(.secondary)
            } else {
                ForEach(avoided.prefix(3)) { task in
                    HStack(spacing: 12) {
                        Button { openActions(task) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(avoidedDetail(task)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button("Start") { startTask(task) }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    .padding(.vertical, 6)
                    if task.id != avoided.prefix(3).last?.id { Divider() }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today’s sessions").font(.headline)
            if todaysSessions.isEmpty {
                Text("No sessions yet today. The hardest part is the first one.").foregroundStyle(.secondary)
            } else {
                ForEach(todaysSessions) { s in
                    HStack {
                        Image(systemName: s.finishedFullBlock ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                            .foregroundStyle(s.finishedFullBlock ? Style.good : Style.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.taskTitle).font(.subheadline)
                            Text("\(s.start.formatted(.dateTime.hour().minute())) · \(Focus.time(s.focusedMinutes))\(s.distractions > 0 ? " · \(s.distractions) distraction\(s.distractions == 1 ? "" : "s")" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func avoidedDetail(_ task: FocusTask) -> String {
        let days = Focus.daysUntouched(task)
        if Focus.neverStarted(task) { return "Not started · \(days) day\(days == 1 ? "" : "s") on your list · \(task.resistance.short) resistance" }
        return "Last worked \(days) day\(days == 1 ? "" : "s") ago · \(task.resistance.short) resistance"
    }

    private func metric(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tasks list + hierarchical detail

struct TasksView: View {
    @EnvironmentObject private var store: FocusStore
    let startTask: (FocusTask) -> Void
    let openActions: (FocusTask) -> Void

    var body: some View {
        List {
            group("To do", tasks: store.activeTasks.sorted { Focus.avoidanceScore($0) > Focus.avoidanceScore($1) })
            group("Done", tasks: store.doneTasks)
        }
        .scrollContentBackground(.hidden)
        .background(Style.canvas)
        .navigationDestination(for: FocusTask.self) { task in
            TaskDetailView(taskId: task.id, start: startTask, openActions: openActions)
        }
    }

    private func group(_ title: String, tasks: [FocusTask]) -> some View {
        Section {
            if tasks.isEmpty { Text("Nothing here for now.").foregroundStyle(.secondary) }
            ForEach(tasks) { task in
                NavigationLink(value: task) { TaskRow(task: task) }
            }
        } header: { Text("\(title) · \(tasks.count)") }
    }
}

struct TaskRow: View {
    let task: FocusTask
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.category.symbol).foregroundStyle(Style.focus).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.headline).strikethrough(task.done)
                HStack(spacing: 6) {
                    Circle().fill(Style.resistanceColor(task.resistance)).frame(width: 7, height: 7)
                    Text("\(task.resistance.short) resistance · \(task.plannedBlocks) × 25 min")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }.padding(.vertical, 4)
    }
}

/// Hierarchical navigation: a task pushes to its detail with session history.
struct TaskDetailView: View {
    @EnvironmentObject private var store: FocusStore
    let taskId: UUID
    let start: (FocusTask) -> Void
    let openActions: (FocusTask) -> Void

    private var task: FocusTask? { store.task(taskId) }

    var body: some View {
        List {
            if let task {
                Section {
                    LabeledContent("Category", value: task.category.label)
                    LabeledContent("Resistance", value: task.resistance.label)
                    LabeledContent("Planned", value: "\(task.plannedBlocks) × 25 min")
                    if let step = task.firstStep, !step.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("First step").font(.caption).foregroundStyle(.secondary)
                            Text(step)
                        }
                    }
                }
                Section {
                    Button { start(task) } label: { Label("Start a focus session", systemImage: "play.fill") }
                    Button { openActions(task) } label: { Label("More actions", systemImage: "ellipsis.circle") }
                }
                Section("Sessions") {
                    let history = store.sessions(for: task)
                    if history.isEmpty {
                        Text("No sessions yet. Starting once is the whole goal.").foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { SessionRow(session: $0) }
                    }
                }
            } else {
                Text("This task was removed.").foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Style.canvas)
        .navigationTitle(task?.title ?? "Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SessionRow: View {
    let session: FocusSession
    var body: some View {
        HStack {
            Image(systemName: session.finishedFullBlock ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                .foregroundStyle(session.finishedFullBlock ? Style.good : Style.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start.formatted(.dateTime.weekday().hour().minute()))
                Text("\(Focus.time(session.focusedMinutes)) of \(Focus.time(session.plannedMinutes))\(session.distractions > 0 ? " · \(session.distractions) distraction\(session.distractions == 1 ? "" : "s")" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Task actions (medium modal sheet)

struct TaskActionsView: View {
    @EnvironmentObject private var store: FocusStore
    @Environment(\.dismiss) private var dismiss
    let task: FocusTask
    let start: (FocusTask) -> Void
    let edit: (FocusTask) -> Void
    @State private var showRemove = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(task.title).font(.headline)
                    Text("\(task.category.label) · \(task.resistance.label)").foregroundStyle(.secondary)
                }
                Section {
                    if !task.done {
                        Button { start(task) } label: { Label("Start a focus session", systemImage: "play.fill") }
                    }
                    Button { edit(task) } label: { Label("Edit task", systemImage: "pencil") }
                    Button { store.toggleDone(task); dismiss() } label: {
                        Label(task.done ? "Mark as not done" : "Mark as done",
                              systemImage: task.done ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                    Button(role: .destructive) { showRemove = true } label: { Label("Remove task", systemImage: "trash") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Style.canvas)
            .navigationTitle("Task actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Remove this task?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Remove task", role: .destructive) { store.remove(task); dismiss() }
            }
        }
    }
}
