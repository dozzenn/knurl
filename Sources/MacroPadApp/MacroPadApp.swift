import SwiftUI
import MacroPadCore

@main
struct MacroPadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel().environmentObject(model)
        } label: {
            Image(systemName: "keyboard.fill")
        }
        .menuBarExtraStyle(.window)

        Window("MacroPad", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 660)
                .onAppear { model.applyActivationPolicy() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Settings live in the window's own sidebar, so the app menu points
            // there rather than opening a second window behind ⌘,.
            CommandGroup(replacing: .appSettings) {
                Button("Settings are in the window sidebar") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
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
    }
}
