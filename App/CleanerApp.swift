import SwiftUI

@main
struct CleanerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Cleaner for xDev") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
