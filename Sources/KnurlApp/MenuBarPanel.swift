import SwiftUI
import KnurlCore

/// The menu bar panel exists for one job: put a different set of keys on the
/// keypad without opening the window. Editing needs the window, so there is
/// nothing here to save — only sets to choose from.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Hairline().padding(.vertical, 6)
            scopeLine
            Hairline().padding(.vertical, 6)

            // An explicit height: a ScrollView inside a menu bar window will
            // not size itself from its content, and left to guess it collapsed
            // and hid the built-in sets entirely.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Your presets")
                    if model.presets.isEmpty {
                        Text("Nothing saved yet.")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                    ForEach(model.presets) { preset in
                        SetRow(title: preset.name,
                               detail: preset.summary,
                               tint: .identity(for: preset.name),
                               active: model.isActive(preset)) {
                            model.apply(preset)
                        }
                    }
                    Row(title: "Save current keys as preset…", icon: "plus.circle") {
                        model.section = .presets
                        AppDelegate.showMainWindow()
                    }

                    SectionLabel(text: "Built in")
                    ForEach(TemplateLibrary.all) { template in
                        SetRow(title: template.name,
                               detail: template.summary,
                               tint: Color(hex: template.tint),
                               active: model.isActive(template)) {
                            model.apply(template)
                        }
                    }
                }
            }
            .frame(height: listHeight)

            Hairline().padding(.vertical, 6)

            Row(title: "Open Knurl", icon: "macwindow") {
                model.section = .keys
                AppDelegate.showMainWindow()
            }
            Row(title: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 8)
        .frame(width: 320)
        .background(PopoverBackground())
        .preferredColorScheme(model.colorScheme)
    }

    /// Sized from the rows actually present, capped so the panel cannot grow
    /// past a sensible menu.
    private var listHeight: CGFloat {
        let rows = model.presets.count + TemplateLibrary.all.count + 1
        let labels: CGFloat = 2 * 30
        let empty: CGFloat = model.presets.isEmpty ? 20 : 0
        return min(CGFloat(rows) * 38 + labels + empty, 372)
    }

    private var header: some View {
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
        .padding(.top, 4)
    }

    /// Choosing a set writes it into one scope, so the panel says which before
    /// you pick rather than after.
    private var scopeLine: some View {
        HStack(spacing: 8) {
            PanelLabel(text: "applies to", colour: Theme.textFaint, size: 9)
            Menu {
                ForEach(model.scopes) { scope in
                    Button(scope.name) { model.selectScope(scope.key) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.currentScope.isGlobal ? "globe" : "app")
                        .font(.system(size: 9, weight: .semibold))
                    Text(model.currentScope.name)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Theme.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}

/// One choosable set: its colour, its name, and a lamp when the keypad is
/// holding exactly this.
private struct SetRow: View {
    let title: String
    let detail: String
    let tint: Color
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.75))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            Lamp(on: active, colour: tint, size: 7)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(active ? Theme.rowSelected : (hovering ? Theme.rowHover : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(hovering && !active ? Theme.outline.opacity(0.3) : .clear,
                                      lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .trackingHover { inside in
            guard inside != hovering else { return }
            withAnimation(Theme.hover) { hovering = inside }
        }
        .onTapGesture { if !active { action() } }
        .padding(.horizontal, 2)
    }
}
