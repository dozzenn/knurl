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

private struct KeyFace: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let mapped: Bool
    var presses: Int?
    let size: CGSize

    var body: some View {
        let radius = min(size.width, size.height) * 0.17

        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: max(13, size.height * 0.24), weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: max(8, size.height * 0.12), weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: size.width, height: size.height)
        .lifted(radius: radius, pressed: selected, depth: 1.1)
        .overlay(alignment: .topTrailing) {
            if let presses, presses > 0 {
                DotMatrixNumber(text: "\(presses)",
                                dot: max(1.2, size.height * 0.02),
                                gap: max(0.7, size.height * 0.011),
                                color: Theme.textFaint)
                    .padding(max(4, size.height * 0.06))
            }
        }
        .overlay(alignment: .bottom) {
            Lamp(on: mapped, colour: selected ? Theme.lampOn : Theme.lampGood,
                 size: max(5, size.height * 0.08))
                .padding(.bottom, max(4, size.height * 0.06))
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct KnobFace: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let size: CGSize

    var body: some View {
        let d = min(size.width, size.height)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.95), Theme.panel],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                .shadow(color: Theme.dropShadow, radius: 5, x: 2, y: 3)

            ForEach(KnobPart.allCases, id: \.self) { part in
                KnobSegment(index: index, part: part, diameter: d)
                    .offset(x: offset(for: part) * d)
            }

            PanelLabel(text: "K\(index)", colour: Theme.textFaint, size: max(7, d * 0.1))
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

    var body: some View {
        let action = InputAction.knob(index, part)
        let selected = model.selectedAction == action
        let mapped = model.binding(for: action).isSet

        Text(part.symbol)
            .font(.system(size: max(9, diameter * 0.19), weight: .semibold))
            .foregroundStyle(selected ? Theme.textOnWell : (mapped ? Theme.text : Theme.textFaint))
            .frame(width: diameter * 0.3, height: diameter * 0.3)
            .background(
                Circle().fill(selected ? Theme.well : Color.white.opacity(mapped ? 0.65 : 0.2))
            )
            .overlay(Circle().strokeBorder(Theme.outline.opacity(selected ? 1 : 0.4), lineWidth: 1))
            .contentShape(Circle())
            .onTapGesture { model.selectedAction = action }
            .help("Knob \(index) \(part.symbol)")
    }
}
