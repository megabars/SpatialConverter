import SwiftUI

@main
struct SpatialConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Remove New Window command — single-window app
            CommandGroup(replacing: .newItem) {}
        }
        .defaultSize(width: 760, height: 540)
    }
}
// MARK: - AppDelegate для обработки drag & drop на иконку

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        // Post notification для ContentView
        NotificationCenter.default.post(
            name: NSNotification.Name("AddFilesToQueue"),
            object: nil,
            userInfo: ["urls": urls]
        )
    }
}

