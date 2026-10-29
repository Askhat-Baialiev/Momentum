import SwiftUI

/// Modal form to add or edit a task. Kept intentionally small: a task only needs
/// the information required to START it.
struct TaskEditor: View {
    @EnvironmentObject private var store: FocusStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FocusTask
    @State private var error: String?
    private let isNew: Bool

    init(task: FocusTask) {
        _draft = State(initialValue: task)
        isNew = (task.title.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title (e.g. HCI report)", text: $draft.title)
                    Picker("Type", selection: $draft.category) {
                        ForEach(FocusTask.Category.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Picker("How hard to start?", selection: $draft.resistance) {
                        ForEach(FocusTask.Resistance.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Stepper("Planned focus blocks: \(draft.plannedBlocks) × 25 min", value: $draft.plannedBlocks, in: 1...8)
                } footer: {
                    Text("Resistance is just how the task feels to you. Momentum shows hard-to-start tasks first.")
                }
                Section("First step (optional)") {
                    TextField("A tiny 2-minute first action", text: Binding(
                        get: { draft.firstStep ?? "" },
                        set: { draft.firstStep = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    Button {
                        draft.firstStep = Focus.suggestedFirstStep(for: draft.title)
                    } label: { Label("Suggest a first step", systemImage: "sparkles") }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Style.canvas)
            .navigationTitle(isNew ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        if let message = Focus.validation(draft) { error = message; return }
        store.commit(draft)
        dismiss()
    }
}
