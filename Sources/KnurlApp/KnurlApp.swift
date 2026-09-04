import SwiftUI
import KnurlCore

@main
struct KnurlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // The window is declared first on purpose: SwiftUI treats the first
        // scene as the primary one, and a menu bar item in that position leaves
        // the app with nothing on screen at launch.
        Window("Knurl", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 660)
                .onAppear { model.applyActivationPolicy() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Settings are a section of the window's own sidebar, so the app
            // menu points there rather than opening a second window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppDelegate.showMainWindow() }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Keypad") {
                Button("Save to keypad") { model.saveToKeyboard() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Save this key only") { model.saveSelectedKey() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                Button("Connect") { model.connect() }
                Button("Disconnect") { model.disconnect() }
                    .disabled(!model.isConnected)
                Button("Refresh devices") { model.refreshDevices() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarPanel().environmentObject(model)
        } label: {
            // A template image so the mark follows the menu bar's own appearance.
            Image(nsImage: Wordmark.menuBarImage())
        }
        .menuBarExtraStyle(.window)
    }
}
