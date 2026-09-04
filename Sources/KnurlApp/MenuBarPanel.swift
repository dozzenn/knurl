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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !model.presets.isEmpty {
                        SectionLabel(text: "Your presets")
                        ForEach(model.presets) { preset in
                            SetRow(title: preset.name,
                                   detail: preset.summary,
                                   tint: .identity(for: preset.name),
                                   active: model.isActive(preset)) {
                                model.apply(preset)
                            }
                        }
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
            .frame(maxHeight: 300)

            Hairline().padding(.vertical, 6)

            Row(title: "Open Knurl", icon: "macwindow") { AppDelegate.showMainWindow() }
            Row(title: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 8)
        .frame(width: 320)
        .background(PopoverBackground())
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
                .fill(active ? Color.black.opacity(0.10)
                      : (hovering ? Color.black.opacity(0.05) : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .onContinuousHover { phase in
            let inside: Bool
            if case .active = phase { inside = true } else { inside = false }
            guard inside != hovering else { return }
            withAnimation(Theme.hover) { hovering = inside }
        }
        .onTapGesture { if !active { action() } }
        .padding(.horizontal, 2)
    }
}
