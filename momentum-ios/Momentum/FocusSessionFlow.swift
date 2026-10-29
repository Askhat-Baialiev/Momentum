import SwiftUI
import Combine

/// The focus session is an ACTION, so it is a modal that shows several views in
/// sequence and ends by closing, revealing the root view it was launched from.
/// Phases: choose a task → prepare the first step → run the timer → review.
struct FocusSessionFlow: View {
    @EnvironmentObject private var store: FocusStore
    @Environment(\.dismiss) private var dismiss

    enum Phase { case choose, prepare, running, summary }

    let preselected: FocusTask?
    @State private var phase: Phase
    @State private var task: FocusTask?
    @State private var minutes = Focus.block
    @State private var firstStep = ""
    @State private var focusedMinutes = 0
    @State private var distractions = 0
    @State private var finishedFull = false

    init(preselected: FocusTask?) {
        self.preselected = preselected
        _phase = State(initialValue: preselected == nil ? .choose : .prepare)
        _task = State(initialValue: preselected)
        _firstStep = State(initialValue: preselected?.firstStep ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose:   chooseView
                case .prepare:  prepareView
                case .running:  runningView
                case .summary:  summaryView
                }
            }
            .background(Style.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .summary {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private var title: String {
        switch phase {
        case .choose: return "Choose a task"
        case .prepare: return "First step"
        case .running: return "Focus"
        case .summary: return "Session done"
        }
    }

    // MARK: Phase 1 — choose

    private var chooseView: some View {
        List {
            Section { Text("What will you focus on? Start with the one you have been avoiding.").foregroundStyle(.secondary) }
            Section {
                ForEach(store.activeTasks.sorted { Focus.avoidanceScore($0) > Focus.avoidanceScore($1) }) { t in
                    Button {
                        task = t
                        firstStep = t.firstStep ?? ""
                        minutes = Focus.block
                        phase = .prepare
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: t.category.symbol).foregroundStyle(Style.focus).frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.title).font(.headline).foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Circle().fill(Style.resistanceColor(t.resistance)).frame(width: 7, height: 7)
                                    Text(t.resistance.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Phase 2 — prepare the first step

    private var prepareView: some View {
        Form {
            if let task {
                Section("Task") {
                    Text(task.title).font(.headline)
                    Text(task.resistance.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Your tiny first step", text: $firstStep, axis: .vertical)
                Button {
                    firstStep = Focus.suggestedFirstStep(for: task?.title ?? "")
                } label: { Label("Suggest a first step", systemImage: "sparkles") }
            } header: { Text("Make it tiny") }
            footer: { Text("You are not committing to finish — only to do this one small thing. That is how starting gets easier.") }

            Section("Focus length") {
                Picker("Length", selection: $minutes) {
                    Text("25 min").tag(25); Text("15 min").tag(15); Text("5 min").tag(5)
                }.pickerStyle(.segmented)
            }
            Section {
                Button {
                    if let task, !firstStep.isEmpty { store.setFirstStep(firstStep, for: task) }
                    phase = .running
                } label: { Label("Start focus", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(task == nil)
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Phase 3 — running timer

    private var runningView: some View {
        RunningSessionView(
            taskTitle: task?.title ?? "",
            firstStep: firstStep,
            minutes: minutes,
            onFinish: { focused, distract, full in
                focusedMinutes = focused; distractions = distract; finishedFull = full
                phase = .summary
            })
    }

    // MARK: Phase 4 — summary

    private var summaryView: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: finishedFull ? "checkmark.seal.fill" : "hand.thumbsup.fill")
                .font(.system(size: 64)).foregroundStyle(finishedFull ? Style.good : Style.focus)
            Text(finishedFull ? "Full block done" : "You showed up").font(.title2.bold())
            VStack(spacing: 6) {
                Text(Focus.time(focusedMinutes)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text("focused on “\(task?.title ?? "")”").foregroundStyle(.secondary)
            }
            if distractions > 0 {
                Text("You noticed \(distractions) distraction\(distractions == 1 ? "" : "s") and stayed anyway.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                if let task { store.logSession(task: task, plannedMinutes: minutes, focusedMinutes: focusedMinutes, distractions: distractions) }
                dismiss()
            } label: { Text("Save & finish").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The live timer screen. Owns its own clock so completion can trigger cleanly.
struct RunningSessionView: View {
    let taskTitle: String
    let firstStep: String
    let minutes: Int
    let onFinish: (_ focusedMinutes: Int, _ distractions: Int, _ full: Bool) -> Void

    @State private var remaining: Int
    @State private var distractions = 0
    @State private var paused = false
    @State private var showEnd = false
    @State private var showDistracted = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(taskTitle: String, firstStep: String, minutes: Int,
         onFinish: @escaping (Int, Int, Bool) -> Void) {
        self.taskTitle = taskTitle; self.firstStep = firstStep; self.minutes = minutes; self.onFinish = onFinish
        _remaining = State(initialValue: minutes * 60)
    }

    private var total: Int { minutes * 60 }
    private var focusedMinutes: Int { max(0, Int((Double(total - remaining) / 60.0).rounded())) }
    private var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().stroke(Style.focus.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : CGFloat(total - remaining) / CGFloat(total))
                    .stroke(Style.focus, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: remaining)
                VStack(spacing: 4) {
                    Text(clock).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(paused ? "Paused" : "Focusing").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(width: 240, height: 240)

            VStack(spacing: 6) {
                Text(taskTitle).font(.headline)
                if !firstStep.isEmpty {
                    Text("Just: \(firstStep)").font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
            }

            if distractions > 0 {
                Label("\(distractions) distraction\(distractions == 1 ? "" : "s") noticed — still here",
                      systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(Style.warn)
            }

            Spacer()

            HStack(spacing: 12) {
                Button { showDistracted = true; distractions += 1 } label: {
                    Label("I got distracted", systemImage: "bell.slash").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { paused.toggle() } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Button(role: .destructive) { showEnd = true } label: {
                Text("End session").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
        .padding(24)
        .onReceive(tick) { _ in
            guard !paused else { return }
            if remaining > 0 { remaining -= 1 }
            if remaining == 0 { onFinish(minutes, distractions, true) }
        }
        .alert("Distraction noticed", isPresented: $showDistracted) {
            Button("Back to it", role: .cancel) {}
        } message: {
            Text("That is normal. You do not have to act on it — the timer is still running. Come back to: \(firstStep.isEmpty ? taskTitle : firstStep)")
        }
        .confirmationDialog("End this session?", isPresented: $showEnd, titleVisibility: .visible) {
            Button("End now · keep \(Focus.time(focusedMinutes))") { onFinish(focusedMinutes, distractions, false) }
            Button("Keep going", role: .cancel) {}
        } message: { Text("Even a few minutes count. Your session will be saved.") }
    }
}
