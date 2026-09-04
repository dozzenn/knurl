import SwiftUI
import MacroPadCore

/// What the menu bar icon drops down. Deliberately small: the keypad's state,
/// one-click profile switching, and the way into everything else. Anything that
/// needs more room lives in the window.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Theme.hairline).padding(.vertical, 6)
            SectionLabel(text: "Profiles")

            if model.profiles.isEmpty {
                Text("No profiles saved yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            ForEach(model.profiles) { entry in
                Row(title: entry.name,
                    icon: "square.stack.3d.up",
                    selected: entry.name == model.activeProfileName,
                    action: { model.switchTo(entry) }) {
                    if entry.name == model.activeProfileName {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Divider().background(Theme.hairline).padding(.vertical, 6)

            Row(title: "Command palette", icon: "command") {
                PaletteController.shared.open()
            } trailing: {
                ShortcutHint(keys: model.hotKeyDisplay)
            }
            Row(title: "Save to keypad", icon: "arrow.down.circle") {
                model.saveToKeyboard()
            } trailing: {
                ShortcutHint(keys: ["⌘", "S"])
            }
            Row(title: "Open MacroPad", icon: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }

            Divider().background(Theme.hairline).padding(.vertical, 6)

            Row(title: "Quit MacroPad", icon: "power") {
                NSApp.terminate(nil)
            } trailing: {
                ShortcutHint(keys: ["⌘", "Q"])
            }
        }
        .padding(.vertical, 8)
        .frame(width: 300)
        // MenuBarExtra hands its content a light system material, so the panel
        // has to paint its own ground or the light-on-dark palette inverts.
        .background(PopoverBackground())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 9) {
            StatusDot(color: model.isConnected ? Theme.online : Theme.textFaint)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(model.isConnected ? model.deviceDetail : "Not connected")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
