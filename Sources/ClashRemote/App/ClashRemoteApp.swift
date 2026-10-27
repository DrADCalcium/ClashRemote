#if os(macOS)
import SwiftUI
#else
import Foundation
import SwiftOpenUI
#endif

#if os(macOS)
@main
#endif
@MainActor
struct ClashRemoteApp: App {
    @State private var state: AppState
    @State private var preferences: AppPreferences

    init() {
        #if DEBUG && os(macOS)
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            WorkspacePreviewRenderer.render(to: CommandLine.arguments[index + 1])
            exit(0)
        }
        #endif
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _state = State(initialValue: AppState(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup("Clash Remote") {
            RootView()
                .environment(state)
                .environment(preferences)
                .frame(minWidth: 980, minHeight: 640)
        }
        #if os(Windows)
        .defaultWindowSize(width: 1240, height: 840)
        .windowSizeConstraints(minWidth: 980, minHeight: 640)
        #else
        .defaultSize(width: 1240, height: 840)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        #endif

        #if os(macOS)
        Settings {
            AppearanceSettingsWindow()
                .environment(preferences)
                .background(WindowPreferences(alwaysOnTop: preferences.alwaysOnTop))
        }
        #endif
    }
}

#if os(Windows)
import BackendWin32
@main
struct WindowsLauncher {
    static func main() { Win32Backend().run(ClashRemoteApp.self) }
}
#endif
