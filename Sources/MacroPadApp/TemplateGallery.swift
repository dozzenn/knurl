import SwiftUI
import MacroPadCore

/// The way in for someone who just plugged a keypad in. Picking a template
/// fills the whole pad at once and writes it, so the first useful thing happens
/// in one click rather than after learning what a HID usage is.
struct TemplateGallery: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: String? = nil

    private var shown: [MacroTemplate] {
        guard let category else { return TemplateLibrary.all }
        return TemplateLibrary.all.filter { $0.category == category }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 12)], spacing: 12) {
                    ForEach(shown) { template in
                        TemplateCard(template: template) {
                            model.apply(template)
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }

            Hairline()
            footer
        }
        .frame(width: 780, height: 560)
        .background(PopoverBackground())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start from a template")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.text)
                    Text("Fills every key and the knob at once. Change anything afterwards.")
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
