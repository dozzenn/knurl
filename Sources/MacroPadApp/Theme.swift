import AppKit
import SwiftUI

// A hardware panel rather than a screen: a light neutral ground, parts lifted
// out of it with a light from the top-left, thin dark outlines that make every
// piece an object with an edge, dark wells for anything that holds data, and
// indicator lamps that light up. Type is monospaced and set in small caps with
// open tracking, the way a device is labelled.

enum Theme {

    // MARK: Ground

    static let ground      = Color(red: 0.765, green: 0.765, blue: 0.769)
    static let panel       = Color(red: 0.827, green: 0.827, blue: 0.831)
    static let panelLift   = Color(red: 0.878, green: 0.878, blue: 0.882)
    /// Wells: inputs, readouts, anything that holds rather than does.
    static let well        = Color(red: 0.055, green: 0.055, blue: 0.059)
    static let wellLift    = Color(red: 0.114, green: 0.114, blue: 0.118)

    /// The hairline that gives every part an edge.
    static let outline     = Color.black.opacity(0.82)
    static let outlineSoft = Color.black.opacity(0.28)
    static let highlight   = Color.white.opacity(0.92)
    static let dropShadow  = Color.black.opacity(0.28)

    // MARK: Ink

    static let text        = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let textMuted   = Color(red: 0.09, green: 0.09, blue: 0.10).opacity(0.62)
    static let textFaint   = Color(red: 0.09, green: 0.09, blue: 0.10).opacity(0.38)
    /// Ink on a dark well.
    static let textOnWell  = Color.white.opacity(0.92)
    static let textOnWellMuted = Color.white.opacity(0.55)

    // MARK: Lamps

    static let lampOn      = Color(red: 0.953, green: 0.792, blue: 0.008)
    static let lampOff     = Color(red: 0.42, green: 0.42, blue: 0.43)
    static let lampGood    = Color(red: 0.20, green: 0.78, blue: 0.38)
    static let lampAlert   = Color(red: 0.90, green: 0.25, blue: 0.22)
    static let accent      = Color(red: 0.36, green: 0.20, blue: 0.92)

    // MARK: Metrics

    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 6
    static let radiusPanel: CGFloat = 14
    static let rowHeight: CGFloat = 36
    static let barHeight: CGFloat = 46
    static let gutter: CGFloat = 16
    static let trafficLightInset: CGFloat = 78

    // MARK: Type
    //
    // Monospace throughout, because a control panel is labelled, not written.
    // macOS has no pixel face to ship, so the retro register comes from the
    // dot-matrix renderer below for readouts and wordmarks, and from small caps
    // with open tracking everywhere else.

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let label      = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    static let rowTitle   = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    static let rowDetail  = Font.system(size: 10.5, weight: .regular, design: .monospaced)
    static let heading    = Font.system(size: 20, weight: .regular, design: .monospaced)
    static let readout    = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: Motion

    static let hover = Animation.easeOut(duration: 0.11)
    static let press = Animation.easeOut(duration: 0.12)
}

// MARK: - Surfaces

/// A part lifted off the ground: light catches the top-left, a soft shadow
/// falls to the bottom-right, and a dark hairline gives it a physical edge.
struct Lifted: ViewModifier {
    var radius: CGFloat = Theme.radius
    var pressed = false
    var depth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(pressed ? Theme.panel : Theme.panelLift)
                    .shadow(color: pressed ? .clear : Theme.dropShadow,
                            radius: 5 * depth, x: 1.5 * depth, y: 2.5 * depth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 0.5)
                    .strokeBorder(pressed ? Color.black.opacity(0.22) : Theme.highlight,
                                  lineWidth: 1)
                    .padding(1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1)
            )
    }
}

/// A dark well — inputs, readouts, the screen part of the panel.
struct Well: ViewModifier {
    var radius: CGFloat = Theme.radiusSmall

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .blur(radius: 0.5)
                    .padding(.bottom, 1)
            )
    }
}

/// A shallow trough that holds lifted parts — the housing for a segmented row.
struct Trough: ViewModifier {
    var radius: CGFloat = Theme.radius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1)
            )
    }
}

extension View {
    func lifted(radius: CGFloat = Theme.radius, pressed: Bool = false, depth: CGFloat = 1) -> some View {
        modifier(Lifted(radius: radius, pressed: pressed, depth: depth))
    }
    func well(radius: CGFloat = Theme.radiusSmall) -> some View {
        modifier(Well(radius: radius))
    }
    func trough(radius: CGFloat = Theme.radius) -> some View {
        modifier(Trough(radius: radius))
    }
}

struct WindowBackground: View {
    var body: some View { Theme.ground.ignoresSafeArea() }
}

struct PopoverBackground: View {
    var body: some View { Theme.ground.ignoresSafeArea() }
}

// MARK: - Lamp

/// An indicator lamp. Lit ones glow a little, because a lamp that only changes
/// colour reads as a coloured dot rather than as something switched on.
struct Lamp: View {
    var on: Bool
    var colour: Color = Theme.lampOn
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(on ? colour : Theme.lampOff)
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.75)
            )
            .overlay(
                Circle()
                    .fill(Color.white.opacity(on ? 0.45 : 0.18))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: -size * 0.17, y: -size * 0.17)
            )
            .shadow(color: on ? colour.opacity(0.75) : .clear, radius: size * 0.5)
    }
}

// MARK: - Type helpers

/// A device label: small, monospaced, upper case, tracked open.
struct PanelLabel: View {
    let text: String
    var colour: Color = Theme.textMuted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(colour)
    }
}

// MARK: - Controls

struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(prominent ? Theme.textOnWell : Theme.text)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(height: compact ? 24 : 30)
            .modifier(PanelButtonSurface(prominent: prominent, pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct PanelButtonSurface: ViewModifier {
    let prominent: Bool
    let pressed: Bool

    func body(content: Content) -> some View {
        if prominent {
            content
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(pressed ? Theme.wellLift : Theme.well)
                        .shadow(color: pressed ? .clear : Theme.dropShadow, radius: 4, x: 1, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.outline, lineWidth: 1)
                )
        } else {
            content.lifted(radius: Theme.radiusSmall, pressed: pressed, depth: 0.7)
        }
    }
}

/// A labelled action, optionally with a lamp that says it is currently on.
struct PanelButton: View {
    let title: String
    var lamp: Bool? = nil
    var prominent = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if let lamp { Lamp(on: lamp, size: 7) }
            }
        }
        .buttonStyle(PanelButtonStyle(prominent: prominent, compact: compact))
    }
}

/// Segments in a trough, each with its own lamp — the site's navigation, which
/// is really a bank of switches.
struct SegmentedSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let on = item.value == selection
                Button { selection = item.value } label: {
                    HStack(spacing: 7) {
                        Text(item.label.uppercased())
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(on ? Theme.textOnWell : Theme.text)
                        Lamp(on: on, size: 7)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .modifier(SegmentSurface(on: on))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .trough(radius: Theme.radius)
    }
}

private struct SegmentSurface: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
        } else {
            content.lifted(radius: Theme.radiusSmall, depth: 0.5)
        }
    }
}

/// A physical switch: a weighted knob that slides in a trough.
struct PanelSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(Theme.panel)
                    .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 1))
                    .frame(width: 42, height: 24)
                Circle()
                    .fill(isOn
                          ? LinearGradient(colors: [Theme.wellLift, Theme.well],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white, Theme.panel],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                    .shadow(color: Theme.dropShadow, radius: 3, x: 1, y: 1.5)
                    .frame(width: 20, height: 20)
                    .padding(2)
            }
            .frame(width: 42, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.press, value: isOn)
    }
}

/// A slider with a black value chip, the way an instrument shows its setting.
struct PanelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var ticks: Int = 0
    var onCommit: (() -> Void)?

    @State private var dragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 22

            ZStack(alignment: .leading) {
                Capsule().fill(Color.clear)
                    .frame(height: 10)
                    .well(radius: 5)

                Capsule()
                    .fill(LinearGradient(colors: [Theme.lampOn.opacity(0.85), Theme.lampOn],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, (w - knob) * fraction + knob / 2), height: 10)
                    .padding(.leading, 0)

                if ticks > 1 {
                    HStack(spacing: 0) {
                        ForEach(0..<ticks, id: \.self) { i in
                            Circle().fill(Color.white.opacity(0.28))
                                .frame(width: 2, height: 2)
                            if i < ticks - 1 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.horizontal, knob / 2)
                }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white, Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.outline, lineWidth: 1))
                    .shadow(color: Theme.dropShadow, radius: dragging ? 5 : 3, x: 1, y: 2)
                    .frame(width: knob, height: 20)
                    .offset(x: (w - knob) * fraction)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let usable = max(1, w - knob)
                        let f = min(1, max(0, (g.location.x - knob / 2) / usable))
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        dragging = false
                        onCommit?()
                    }
            )
        }
        .frame(height: 24)
        .animation(Theme.press, value: dragging)
    }
}

/// A value in a black chip — a readout, not a caption.
struct Readout: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.readout)
            .foregroundStyle(Theme.textOnWell)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .well(radius: 5)
    }
}

// MARK: - Key caps

struct KeyCap: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 20)
            .frame(height: 20)
            .padding(.horizontal, 4)
            .lifted(radius: 5, depth: 0.45)
    }
}

struct ShortcutHint: View {
    let keys: [String]
    var emphasized = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(text: key, emphasized: emphasized)
            }
        }
    }
}

// MARK: - Rows

struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconTint: Color = Theme.textMuted
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Theme.text : iconTint)
                    .frame(width: 16)
            }
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.rowDetail)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(selected ? Color.black.opacity(0.10) : (hovering ? Color.black.opacity(0.05) : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
        .onTapGesture { action?() }
    }
}

extension Row where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil,
         iconTint: Color = Theme.textMuted, selected: Bool = false, action: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon, iconTint: iconTint,
                  selected: selected, action: action) { EmptyView() }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        PanelLabel(text: text, colour: Theme.textFaint)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.outlineSoft.opacity(0.35)).frame(height: 1) }
}

struct StatusDot: View {
    let color: Color
    var body: some View { Lamp(on: true, colour: color, size: 8) }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Theme.textFaint)
            PanelLabel(text: title, colour: Theme.textMuted, size: 11)
            if let message {
                Text(message)
                    .font(Theme.rowDetail)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Dot matrix

/// Characters drawn as a dot field. This is where the retro register actually
/// comes from: macOS ships no pixel face, so the wordmark and the readouts are
/// plotted rather than typeset.
struct DotMatrixNumber: View {
    let text: String
    var dot: CGFloat = 3
    var gap: CGFloat = 1.5
    var color: Color = Theme.text

    private static let glyphs: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "001", "001", "001"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        "A": ["111", "101", "111", "101", "101"],
        "C": ["111", "100", "100", "100", "111"],
        "D": ["110", "101", "101", "101", "110"],
        "E": ["111", "100", "111", "100", "111"],
        "K": ["101", "101", "110", "101", "101"],
        "M": ["101", "111", "111", "101", "101"],
        "O": ["111", "101", "101", "101", "111"],
        "P": ["111", "101", "111", "100", "100"],
        "R": ["111", "101", "111", "110", "101"],
        "S": ["111", "100", "111", "001", "111"],
        ",": ["000", "000", "000", "010", "100"],
        ".": ["000", "000", "000", "000", "010"],
        "%": ["101", "001", "010", "100", "101"],
        "-": ["000", "000", "111", "000", "000"],
        " ": ["000", "000", "000", "000", "000"],
    ]

    private var pitch: CGFloat { dot + gap }

    var body: some View {
        Canvas { context, _ in
            var originX: CGFloat = 0
            for character in text.uppercased() {
                let rows = Self.glyphs[character] ?? Self.glyphs[" "]!
                for (r, row) in rows.enumerated() {
                    for (c, bit) in row.enumerated() where bit == "1" {
                        let rect = CGRect(x: originX + CGFloat(c) * pitch,
                                          y: CGFloat(r) * pitch,
                                          width: dot, height: dot)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                originX += 3 * pitch + gap * 2
            }
        }
        .frame(width: CGFloat(text.count) * (3 * pitch + gap * 2),
               height: 5 * pitch - gap)
    }
}
