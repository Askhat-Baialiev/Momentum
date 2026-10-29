import SwiftUI

@main
struct MomentumApp: App {
    @StateObject private var store = FocusStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Style.focus)
        }
    }
}
