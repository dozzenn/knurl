import SwiftUI
import MacroPadCore

@main
struct MacroPadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
        } label: {
            Image(systemName: "keyboard.fill")
        }
        .menuBarExtraStyle(.window)

        Window("MacroPad", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
                .background(WindowBackground())
                .preferredColorScheme(.dark)
                .onAppear { model.applyActivationPolicy() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Device") {
                Button("Connect") { model.connect() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Disconnect") { model.disconnect() }
                    .disabled(!model.isConnected)
                Divider()
                Button("Refresh device list") { model.refreshDevices() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Probe report ids") { model.probeReportIds() }
                Divider()
                Button("Save to keypad") { model.saveToKeyboard() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Save this key only") { model.saveSelectedKey() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                Button("Import preset…") { model.importPreset() }
                Button("Export preset…") { model.exportPreset() }

            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .background(WindowBackground())
                .preferredColorScheme(.dark)
        }
    }
}
