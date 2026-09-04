import SwiftUI
import MacroPadCore

/// The pad itself, drawn where the keys physically sit. Selecting a control is
/// the most repeated action in the app, so selection is a background change
/// only — nothing scales, nothing slides.
struct PadPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            GeometryReader { geo in
                let content = model.layout.contentSize
                let scale = min((geo.size.width - 40) / content.width,
                                (geo.size.height - 40) / content.height,
                                6.5)
                ZStack(alignment: .topLeading) {
                    ForEach(model.layout.controls) { control in
                        ControlView(control: control, scale: scale)
                            .position(x: (control.position.x + control.position.width / 2) * scale,
                                      y: (control.position.y + control.position.height / 2) * scale)
                    }
                }
                .frame(width: content.width * scale, height: content.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)

            Hairline()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(LayoutLibrary.all) { layout in
                    Button {
                        model.layout = layout
                    } label: {
                        Text(layout.name == model.layout.name ? "✓ \(layout.name)" : layout.name)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    Text(model.layout.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Text("\(configuredCount) mapped")
                .font(Theme.caption)
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 34)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.selectedAction.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            let summary = model.binding(for: model.selectedAction).summary
            if summary.isEmpty {
                Text("not mapped")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
            } else {
                Text(summary)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if model.layout.layerCount > 1 {
                Text("Layer \(model.layer + 1)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 34)
    }

    private var configuredCount: Int {
        model.profile.configured(layerCount: model.layout.layerCount).count
    }
}

private struct ControlView: View {
    @EnvironmentObject private var model: AppModel
    let control: PhysicalControl
    let scale: CGFloat

    var body: some View {
        switch control.kind {
        case .button(let index):
            let action = InputAction.key(index)
            ButtonFace(title: "\(index)",
                       subtitle: model.binding(for: action).summary,
                       selected: model.selectedAction == action,
                       mapped: model.binding(for: action).isSet,
                       size: CGSize(width: control.position.width * scale,
                                    height: control.position.height * scale))
                .onTapGesture { model.selectedAction = action }
        case .knob(let index):
            KnobFace(index: index,
                     size: CGSize(width: control.position.width * scale,
                                  height: control.position.height * scale))
        }
    }
}

/// A keycap: a raised dark surface with a bright top edge, the way light
/// catches a real key. Mapped keys carry an accent underline rather than a
/// filled background, so a full pad still reads as a pad and not as a chart.
private struct ButtonFace: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let mapped: Bool
    let size: CGSize

    @State private var hovering = false

    var body: some View {
        let radius = min(size.width, size.height) * 0.16

        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: max(11, size.height * 0.22), weight: .semibold, design: .rounded))
                .foregroundStyle(mapped ? Theme.text : Theme.textMuted)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: max(8, size.height * 0.125), weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(hovering ? Theme.rowHover : Theme.fill)
                )
        )
        .overlay(alignment: .bottom) {
            if mapped {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.accent.opacity(selected ? 1 : 0.55))
                    .frame(width: size.width * 0.42, height: 2)
                    .padding(.bottom, max(4, size.height * 0.07))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.hairline,
                              lineWidth: selected ? 1.5 : 1)
        )
        .overlay(alignment: .top) {
            // Bright top edge — the material catching light from above.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .trim(from: 0.62, to: 0.88)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

/// Knobs expose three targets — turn left, press, turn right — arranged the way
/// the hand moves, so the control maps to what it changes.
private struct KnobFace: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let size: CGSize

    var body: some View {
        let d = min(size.width, size.height)
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.22))
                .overlay(Circle().fill(Theme.fill))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

            ForEach(KnobPart.allCases, id: \.self) { part in
                KnobSegment(index: index, part: part, diameter: d)
                    .offset(x: offset(for: part) * d)
            }

            Text("K\(index)")
                .font(.system(size: max(7.5, d * 0.12), weight: .medium))
                .foregroundStyle(Theme.textFaint)
                .offset(y: d * 0.33)
        }
        .frame(width: size.width, height: size.height)
    }

    private func offset(for part: KnobPart) -> CGFloat {
        switch part {
        case .left: return -0.27
        case .push: return 0
        case .right: return 0.27
        }
    }
}

private struct KnobSegment: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let part: KnobPart
    let diameter: CGFloat

    @State private var hovering = false

    var body: some View {
        let action = InputAction.knob(index, part)
        let selected = model.selectedAction == action
        let mapped = model.binding(for: action).isSet

        Text(part.symbol)
            .font(.system(size: max(9, diameter * 0.2), weight: .semibold))
            .foregroundStyle(mapped ? Theme.text : Theme.textFaint)
            .frame(width: diameter * 0.32, height: diameter * 0.32)
            .background(
                Circle().fill(selected ? Theme.accent.opacity(0.30)
                              : (hovering ? Theme.rowHover : (mapped ? Theme.fillStrong : .clear)))
            )
            .overlay(
                Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Circle())
            .onTapGesture { model.selectedAction = action }
            .onHover { h in withAnimation(Theme.hover) { hovering = h } }
            .help("Knob \(index) \(part.symbol)")
    }
}
