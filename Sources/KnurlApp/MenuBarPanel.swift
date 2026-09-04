import SwiftUI
import KnurlCore

/// A small version of the panel for the menu bar: what the keypad is holding,
/// and the sets you can put on it. Everything else lives in the window.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Lamp(on: model.isConnected, colour: Theme.lampGood, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.deviceLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    PanelLabel(text: model.isConnected ? model.deviceDetail : "not connected",
                               colour: Theme.textFaint, size: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            SectionLabel(text: "Key sets")
            ForEach(model.scopes) { scope in
                Row(title: scope.name,
                    subtitle: scope.isGlobal ? "everywhere" : "only in this app",
                    icon: scope.isGlobal ? "globe" : "app",
                    selected: scope.key == model.liveScopeKey,
                    action: { model.load(scope) }) {
                    Lamp(on: scope.key == model.liveScopeKey, colour: Theme.lampGood, size: 6)
                }
            }

            Hairline().padding(.vertical, 6)

            Row(title: "Save to keypad",
                subtitle: model.isConnected ? nil : "connect first",
                icon: "arrow.down.circle") { model.saveToKeyboard() }
            Row(title: "Open Knurl", icon: "macwindow") { AppDelegate.showMainWindow() }
            Row(title: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 8)
        .frame(width: 300)
        .background(PopoverBackground())
    }
}
