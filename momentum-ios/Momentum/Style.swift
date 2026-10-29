import SwiftUI

/// Shared colours so every screen reads as one system in light and dark mode.
enum Style {
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let blue = Color.accentColor
    static let focus = Color(red: 0.36, green: 0.42, blue: 0.95)   // calm indigo for focus
    static let warn = Color(red: 0.86, green: 0.47, blue: 0.08)    // avoided / attention
    static let good = Color.green

    static func resistanceColor(_ r: FocusTask.Resistance) -> Color {
        switch r { case .low: return .green; case .medium: return warn; case .high: return .red }
    }
}
