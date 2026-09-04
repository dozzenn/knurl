import SwiftUI
import MacroPadCore

@main
struct MacroPadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("MacroPad", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
                .background(WindowBackground())
                .preferredColorScheme(.dark)
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
                Button("Upload selected control") { model.uploadSelected() }
                    .keyboardShortcut("u", modifiers: [.command])
                Button("Upload everything") { model.uploadAll() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
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
