import SwiftUI
import MacroPadCore

/// The way in for someone who just plugged a keypad in. Picking a template
/// fills the whole pad at once and writes it, so the first useful thing happens
/// in one click rather than after learning what a HID usage is.
struct TemplateGallery: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: String? = nil
    @State private var showSaveSheet = false
    @State private var newName = ""

    private var shown: [MacroTemplate] {
        guard let category else { return TemplateLibrary.all }
        return TemplateLibrary.all.filter { $0.category == category }
    }

    private var showBuiltIn: Bool { category != "Yours" }
    private var showMine: Bool { category == nil || category == "Yours" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showMine {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Your presets")
                                    .font(Theme.sectionLabel).tracking(0.3)
                                    .foregroundStyle(Theme.textFaint)
                                Spacer()
                                BarAction(title: "Save current keys…", prominent: true) {
                                    newName = model.currentScope.name
                                    showSaveSheet = true
                                }
                            }
                            if model.presets.isEmpty {
                                Text("Nothing saved yet. “Save current keys…” keeps whatever is on screen so you can drop it onto any app later.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 12)],
                                          spacing: 12) {
                                    ForEach(model.presets) { preset in
                                        PresetCard(preset: preset,
                                                   onApply: { model.apply(preset); dismiss() },
                                                   onDelete: { model.deletePreset(preset) })
                                    }
                                }
                            }
                        }
                    }

                    if showBuiltIn {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Built in")
                                .font(Theme.sectionLabel).tracking(0.3)
                                .foregroundStyle(Theme.textFaint)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 12)],
                                      spacing: 12) {
                                ForEach(shown) { template in
                                    TemplateCard(template: template) {
                                        model.apply(template)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Hairline()
            footer
        }
        .frame(width: 800, height: 580)
        .background(PopoverBackground())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSaveSheet) {
            SavePresetSheet(name: $newName) { name, summary in
                model.savePreset(named: name, summary: summary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Presets")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.text)
                    Text("A whole set of keys in one click, applied to \(model.currentScope.name). Change anything afterwards.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.fill))
                }
                .buttonStyle(PressableStyle())
            }

            HStack(spacing: 5) {
                CategoryChip(title: "All", selected: category == nil) { category = nil }
                CategoryChip(title: "Yours", selected: category == "Yours") { category = "Yours" }
                ForEach(TemplateLibrary.categories, id: \.self) { name in
                    CategoryChip(title: name, selected: category == name) { category = name }
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isConnected ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(model.isConnected ? Theme.online : Theme.warning)
            Text(model.isConnected
                 ? "Choosing a template writes it to \(model.deviceLabel) straight away."
                 : "No keypad connected — a template will be loaded into the editor and saved when you connect.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

private struct CategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textMuted)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    Capsule().fill(selected ? Theme.accent : (hovering ? Theme.rowHover : Theme.fill))
                )
                .overlay(Capsule().strokeBorder(selected ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct TemplateCard: View {
    let template: MacroTemplate
    let onAdd: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: template.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fill))
                Spacer()
                Text(template.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Capsule().fill(Theme.fill))
            }
            .padding(.bottom, 11)

            Text(template.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(template.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            // What it actually puts on the pad, so nothing is a surprise.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(template.buttons.enumerated()), id: \.offset) { i, step in
                    SlotLine(slot: "\(i + 1)", label: step.label)
                }
                ForEach(Array(template.knob.enumerated()), id: \.offset) { i, step in
                    if let step {
                        SlotLine(slot: ["↺", "⏺", "↻"][i], label: step.label)
                    }
                }
            }
            .padding(.top, 11)

            if let note = template.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.warning.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

            Spacer(minLength: 12)

            Button(action: onAdd) {
                Text("Use this")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.accent))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 268, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Theme.rowHover : Theme.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(hovering ? Color.white.opacity(0.16) : Theme.hairline, lineWidth: 1)
        )
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct SlotLine: View {
    let slot: String
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            KeyCap(text: slot)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        }
    }
}


/// One of the user's own saved sets.
private struct PresetCard: View {
    @EnvironmentObject private var model: AppModel
    let preset: Preset
    let onApply: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var mapped: Int { preset.profile.bindings.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .raised(radius: 8, depth: 0.4)
                Spacer()
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Delete this preset")
                }
            }
            .padding(.bottom, 11)

            Text(preset.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(preset.summary.isEmpty
                 ? "\(mapped) key\(mapped == 1 ? "" : "s") saved"
                 : preset.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Spacer(minLength: 12)

            Button(action: onApply) {
                Text("Use this")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .raised(radius: Theme.radius, depth: 0.5)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .raised(radius: 12, depth: hovering ? 0.9 : 0.7)
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct SavePresetSheet: View {
    @Binding var name: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Save these keys as a preset")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .recessed(radius: Theme.radius)
            TextField("What is it for? (optional)", text: $summary)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .recessed(radius: Theme.radius)
            HStack {
                Spacer()
                BarAction(title: "Cancel") { dismiss() }
                BarAction(title: "Save", keys: ["⏎"], prominent: true, action: save)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(PopoverBackground())
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, summary.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
