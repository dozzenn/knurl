import SwiftUI
import MacroPadCore

/// The keypad itself, drawn where the keys physically sit — a plate with keys
/// standing proud of it. Selecting a key is the most repeated action here, so
/// selection is a lamp and an outline, not motion.
struct PadPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            GeometryReader { geo in
                let content = model.layout.contentSize
                let scale = min((geo.size.width - 56) / content.width,
                                (geo.size.height - 56) / content.height,
                                7.0)
                ZStack(alignment: .topLeading) {
                    ForEach(model.layout.controls) { control in
                        ControlView(control: control, scale: scale)
                            .position(x: (control.position.x + control.position.width / 2) * scale,
                                      y: (control.position.y + control.position.height / 2) * scale)
                    }
                }
                .frame(width: content.width * scale, height: content.height * scale)
                .padding(22)
                .trough(radius: Theme.radiusPanel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Theme.gutter)

            Hairline()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(LayoutLibrary.all) { layout in
                    Button(layout.name) { model.layout = layout }
                }
            } label: {
                HStack(spacing: 7) {
                    PanelLabel(text: model.layout.name, colour: Theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
            PanelLabel(text: "\(configuredCount) mapped", colour: Theme.textFaint, size: 9)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 34)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            PanelLabel(text: model.selectedAction.displayName, colour: Theme.text)
            let summary = model.binding(for: model.selectedAction).summary
            Text(summary.isEmpty ? "not mapped" : summary)
                .font(Theme.rowDetail)
                .foregroundStyle(summary.isEmpty ? Theme.textFaint : Theme.textMuted)
                .lineLimit(1)
            Spacer()
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
            KeyFace(title: "\(index)",
                    subtitle: model.binding(for: action).summary,
                    selected: model.selectedAction == action,
                    mapped: model.binding(for: action).isSet,
                    presses: model.statsEnabled ? model.presses(for: action) : nil,
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

/// A keycap: a body with walls, a top face that catches the light, and a lamp
/// in the skirt. Pressing sinks the face into the body rather than moving the
/// whole cap, which is what a real key does.
private struct KeyFace: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let mapped: Bool
    var presses: Int?
    let size: CGSize

    @State private var hovering = false

    private var faceColours: [Color] {
        if selected { return [Theme.capSunkHigh, Theme.capSunkLow] }
        return mapped ? [Theme.capFaceHigh, Theme.capFaceLow]
                      : [Theme.capIdleHigh, Theme.capIdleLow]
    }

    var body: some View {
        let radius = min(size.width, size.height) * 0.19
        let inset = max(3, min(size.width, size.height) * 0.055)
        let pad = max(6, size.width * 0.11)

        ZStack {
            // Body — the walls of the cap.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.capBodyHigh, Theme.capBodyLow],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.outline, lineWidth: 1)
                )
                .shadow(color: Theme.dropShadow, radius: selected ? 2 : 6,
                        x: 1, y: selected ? 1 : 4)

            // Top face — sunk when the key is the one being edited.
            RoundedRectangle(cornerRadius: radius * 0.78, style: .continuous)
                .fill(LinearGradient(colors: faceColours, startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: radius * 0.78, style: .continuous)
                        .strokeBorder(Color.black.opacity(selected ? 0.30 : 0.16), lineWidth: 1)
                )
                .padding(EdgeInsets(top: inset * 0.75, leading: inset,
                                    bottom: inset * 1.5, trailing: inset))
                .shadow(color: .black.opacity(selected ? 0.22 : 0), radius: 3, y: 1)

            VStack(spacing: max(2, size.height * 0.03)) {
                Text(title)
                    .font(.system(size: max(12, size.height * 0.2), weight: .semibold,
                                  design: .monospaced))
                    .foregroundStyle(Theme.text)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: max(8, size.height * 0.105), weight: .medium,
                                      design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: size.width - pad * 2)
                }
            }
            .padding(.horizontal, pad)
            .padding(.top, inset * 0.4)
            .padding(.bottom, inset * 1.1)

        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            if let presses, presses > 0 {
                DotMatrixNumber(text: "\(presses)",
                                dot: max(1.1, size.height * 0.018),
                                gap: max(0.6, size.height * 0.010),
                                color: Theme.textFaint)
                    .padding(inset * 1.6)
            }
        }
        .scaleEffect(hovering && !selected ? 1.015 : 1)
        .animation(Theme.press, value: selected)
        .animation(Theme.hover, value: hovering)
        .onHover { h in hovering = h }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A knob, drawn as one: a ring of ticks, a bezel, a turned metal face and a
/// pointer. Its three actions are the two flanks and the cap — turn left, turn
/// right, press — so the control matches the movements it records.
private struct KnobFace: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let size: CGSize

    var body: some View {
        let d = min(size.width, size.height)
        let bodyD = d * 0.54

        ZStack {
            TickRing(diameter: d, count: 15)

            KnobWing(index: index, part: .left, diameter: d)
            KnobWing(index: index, part: .right, diameter: d)

            // Bezel
            Circle()
                .fill(LinearGradient(colors: [Theme.bezelHigh, Theme.bezelLow],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: bodyD + d * 0.055, height: bodyD + d * 0.055)
                .shadow(color: Theme.dropShadow, radius: 5, x: 1, y: 3)

            // Turned metal face
            Circle()
                .fill(AngularGradient(colors: [
                    Theme.turnedMetal(0.97), Theme.turnedMetal(0.80), Theme.turnedMetal(0.94),
                    Theme.turnedMetal(0.76), Theme.turnedMetal(0.97), Theme.turnedMetal(0.82),
                    Theme.turnedMetal(0.93), Theme.turnedMetal(0.78), Theme.turnedMetal(0.97),
                ], center: .center))
                .overlay(
                    Circle().fill(
                        LinearGradient(colors: [Theme.highlight.opacity(0.8), Color.clear],
                                       startPoint: .topLeading, endPoint: .center))
                )
                .overlay(Circle().strokeBorder(Color.black.opacity(0.30), lineWidth: 1))
                .frame(width: bodyD, height: bodyD)

            // Pointer, at the position that says which way it last went.
            Circle()
                .fill(pushMapped ? Theme.lampOn : Theme.lampOff)
                .frame(width: d * 0.055, height: d * 0.055)
                .shadow(color: pushMapped ? Theme.lampOn.opacity(0.8) : .clear, radius: 3)
                .offset(y: -bodyD * 0.33)

            PanelLabel(text: "K\(index)", colour: Theme.textFaint, size: max(7, d * 0.085))
                .offset(y: d * 0.44)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Circle().inset(by: d * 0.19))
        .onTapGesture { model.selectedAction = InputAction.knob(index, .push) }
        .overlay(
            Circle()
                .strokeBorder(pushSelected ? Theme.lampOn : .clear, lineWidth: 2)
                .frame(width: bodyD + d * 0.055, height: bodyD + d * 0.055)
        )
    }

    private var pushMapped: Bool { model.binding(for: InputAction.knob(index, .push)).isSet }
    private var pushSelected: Bool { model.selectedAction == InputAction.knob(index, .push) }
}

/// The ticks engraved around a knob.
private struct TickRing: View {
    let diameter: CGFloat
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let t = Double(i) / Double(count - 1)
                let angle = -135.0 + t * 270.0
                Capsule()
                    .fill(Theme.textFaint)
                    .frame(width: max(1, diameter * 0.012),
                           height: diameter * (i == 0 || i == count - 1 || i == count / 2 ? 0.07 : 0.045))
                    .offset(y: -diameter * 0.38)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// One side of the knob: the hit target for turning that way.
private struct KnobWing: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let part: KnobPart
    let diameter: CGFloat

    @State private var hovering = false

    var body: some View {
        let action = InputAction.knob(index, part)
        let selected = model.selectedAction == action
        let mapped = model.binding(for: action).isSet
        let x = (part == .left ? -1.0 : 1.0) * diameter * 0.46

        VStack(spacing: diameter * 0.02) {
            Text(part.symbol)
                .font(.system(size: diameter * 0.17, weight: .semibold))
                .foregroundStyle(selected ? Theme.textOnWell : (mapped ? Theme.text : Theme.textFaint))
            Lamp(on: mapped, colour: selected ? Theme.lampOn : Theme.lampGood,
                 size: diameter * 0.055)
        }
        .frame(width: diameter * 0.28, height: diameter * 0.4)
        .modifier(WingSurface(selected: selected, hovering: hovering,
                              radius: diameter * 0.07))
        .contentShape(RoundedRectangle(cornerRadius: diameter * 0.07, style: .continuous))
        .onTapGesture { model.selectedAction = action }
        .offset(x: x)
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
        .help("Knob \(index) \(part.symbol)")
    }
}

private struct WingSurface: ViewModifier {
    let selected: Bool
    let hovering: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if selected {
            content
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
        } else {
            content.lifted(radius: radius, depth: hovering ? 0.9 : 0.6)
        }
    }
}
