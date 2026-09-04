import AppKit
import SwiftUI

// The visual language: one dark translucent surface, a tight type scale, dense
// rows, and motion reserved for things a pointer does. Anything reachable from
// the keyboard is deliberately instant — this app is used in short bursts and
// animation on a repeated action reads as lag.

enum Theme {

    // MARK: Ground
    //
    // A neutral mid grey, not black. Depth here comes from a light from the
    // top-left and a shadow to the bottom-right, and neither is visible on a
    // surface that is already at one end of the range — the ground has to sit
    // in the middle for a control to look raised out of it or pressed into it.

    static let ground      = Color(red: 0.216, green: 0.216, blue: 0.224)
    static let groundDeep  = Color(red: 0.165, green: 0.165, blue: 0.173)
    static let groundLift  = Color(red: 0.251, green: 0.251, blue: 0.259)

    /// The two lights that define every surface.
    static let lightEdge   = Color.white.opacity(0.11)
    static let darkEdge    = Color.black.opacity(0.42)

    // MARK: Colour

    static let text        = Color.white.opacity(0.92)
    static let textMuted   = Color.white.opacity(0.58)
    static let textFaint   = Color.white.opacity(0.36)

    static let hairline    = Color.white.opacity(0.07)
    static let rowHover    = Color.white.opacity(0.05)
    static let rowSelected = Color.white.opacity(0.09)
    static let fill        = Color.white.opacity(0.06)
    static let fillStrong  = Color.white.opacity(0.11)

    static let accent      = Color(red: 1.00, green: 0.42, blue: 0.38)
    static let online      = Color(red: 0.40, green: 0.86, blue: 0.45)
    static let warning     = Color(red: 1.00, green: 0.76, blue: 0.28)

    static let scrim       = Color.black.opacity(0.0)

    // MARK: Metrics

    static let windowRadius: CGFloat = 12
    static let radius: CGFloat = 9
    static let radiusSmall: CGFloat = 6
    static let rowHeight: CGFloat = 34
    static let barHeight: CGFloat = 44
    static let gutter: CGFloat = 14
    static let trafficLightInset: CGFloat = 76

    // MARK: Type

    static let rowTitle    = Font.system(size: 13, weight: .medium)
    static let rowSubtitle = Font.system(size: 11, weight: .regular)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let caption     = Font.system(size: 11, weight: .regular)
    static let keycap      = Font.system(size: 10.5, weight: .medium, design: .rounded)
    static let mono        = Font.system(size: 10.5, weight: .regular, design: .monospaced)

    // MARK: Motion

    static let hover  = Animation.easeOut(duration: 0.12)
    static let press  = Animation.easeOut(duration: 0.13)
}

// MARK: - Soft machine surfaces

/// A surface lifted out of the ground: highlight up-left, shadow down-right,
/// and a bright inner edge where the light catches the top lip.
struct Raised: ViewModifier {
    var radius: CGFloat = Theme.radius
    var depth: CGFloat = 1
    var pressed = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(pressed ? Theme.groundDeep : Theme.groundLift)
                    .shadow(color: pressed ? .clear : Theme.lightEdge,
                            radius: 6 * depth, x: -3 * depth, y: -3 * depth)
                    .shadow(color: pressed ? .clear : Theme.darkEdge,
                            radius: 10 * depth, x: 5 * depth, y: 5 * depth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: pressed
                                       ? [Color.black.opacity(0.30), Color.white.opacity(0.04)]
                                       : [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
    }
}

/// A well pressed into the ground — tracks, fields, and anything that holds
/// something rather than does something.
struct Recessed: ViewModifier {
    var radius: CGFloat = Theme.radius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.groundDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.black.opacity(0.45), Color.white.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
    }
}

extension View {
    func raised(radius: CGFloat = Theme.radius, depth: CGFloat = 1, pressed: Bool = false) -> some View {
        modifier(Raised(radius: radius, depth: depth, pressed: pressed))
    }
    func recessed(radius: CGFloat = Theme.radius) -> some View {
        modifier(Recessed(radius: radius))
    }
    /// The warm halo an active control carries.
    func activeGlow(_ colour: Color, on: Bool, radius: CGFloat = 7) -> some View {
        shadow(color: on ? colour.opacity(0.55) : .clear, radius: radius)
    }
}

// MARK: - Accessibility-aware translucency

/// The window's single blurred surface. Falls back to a solid fill when the
/// user has asked for reduced transparency.
struct WindowSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .windowBackground : .hudWindow
    }
}

struct WindowBackground: View {
    var body: some View {
        Theme.ground.ignoresSafeArea()
    }
}

// MARK: - Key caps

/// A single key rendered the way a keyboard shortcut is drawn in menus:
/// small, square-ish, one glyph. Used both for shortcut hints and for the
/// recorded macro sequence, so a recorded step and a hint read as the same
/// kind of object.
struct KeyCap: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(Theme.keycap)
            .foregroundStyle(emphasized ? Theme.text : Theme.textMuted)
            .frame(minWidth: 19)
            .frame(height: 19)
            .padding(.horizontal, 4)
            .raised(radius: Theme.radiusSmall, depth: 0.4)
    }
}

/// A shortcut such as ⇧⌘U rendered as separate caps.
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

/// The list primitive. Dense, one line of content, an optional trailing
/// accessory, and a background that only changes on hover or selection —
/// nothing moves, because these rows are stepped through quickly.
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Theme.text : iconTint)
                    .frame(width: 16)
            }
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.rowSubtitle)
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 9)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(selected ? Theme.rowSelected : (hovering ? Theme.rowHover : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
        Text(text)
            .font(Theme.sectionLabel)
            .tracking(0.3)
            .foregroundStyle(Theme.textFaint)
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Press feedback lands on pointer-down and is over in ~130ms, so the control
/// feels like it heard the click rather than like it is playing an animation.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct BarButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Theme.text : Theme.textMuted)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .modifier(BarButtonSurface(prominent: prominent, pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct BarButtonSurface: ViewModifier {
    let prominent: Bool
    let pressed: Bool

    func body(content: Content) -> some View {
        if prominent || pressed {
            content.raised(radius: Theme.radius, depth: 0.55, pressed: pressed)
        } else {
            content
        }
    }
}

/// A hoverable bar control that also carries a shortcut hint.
struct BarAction: View {
    let title: String
    var keys: [String] = []
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if !keys.isEmpty { ShortcutHint(keys: keys, emphasized: prominent) }
            }
        }
        .buttonStyle(BarButtonStyle(prominent: prominent || hovering))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

// MARK: - Segmented control

/// Replaces the stock segmented picker: same job, but flat, dense and dark so
/// it belongs to the surface rather than sitting on top of it.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, label: String, icon: String?)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isOn = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 5) {
                        if let icon = item.icon {
                            Image(systemName: icon).font(.system(size: 11, weight: .medium))
                        }
                        Text(item.label).font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    }
                    .foregroundStyle(isOn ? Theme.text : Theme.textMuted)
                    .padding(.horizontal, 11)
                    .frame(height: 25)
                    .modifier(SegmentSurface(on: isOn))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .padding(3)
        .recessed(radius: Theme.radius)
    }
}

private struct SegmentSurface: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.raised(radius: Theme.radiusSmall, depth: 0.45) } else { content }
    }
}

// MARK: - Misc chrome

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// Status dot with a soft halo, so "connected" reads at a glance without a label.
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().fill(color.opacity(0.28)).frame(width: 13, height: 13))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            if let message {
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - Top-bar cards

/// A pressable container for the two things the user identifies the session by:
/// which keypad is connected and which profile is loaded. Bigger and heavier
/// than a menu button because these answer questions at a glance, not on click.
struct Pill<Content: View>: View {
    var active = false
    @ViewBuilder let content: Content
    let action: () -> Void

    @State private var hovering = false

    init(active: Bool = false, @ViewBuilder content: () -> Content, action: @escaping () -> Void) {
        self.active = active
        self.content = content()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 12)
                .frame(height: 42)
                .raised(radius: 11, depth: hovering ? 0.9 : 0.7, pressed: active)
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.985))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

/// Popovers get their own opaque ground: the window is already one translucent
/// layer, and stacking a second one washes the text out.
struct PopoverBackground: View {
    var body: some View {
        Theme.ground.ignoresSafeArea()
    }
}

// MARK: - Tactile controls

/// A slider you feel rather than read.
///
/// Tracks the pointer 1:1 from the moment it goes down — no animation on the
/// drag itself, because the value must sit under the finger. The knob grows
/// slightly while held, which is the only cue that needs motion.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// Number of tick dots under the track; 0 hides them.
    var ticks: Int = 0
    var tint: Color = Theme.accent
    var onCommit: (() -> Void)?

    @State private var dragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let knob: CGFloat = dragging ? 20 : 17

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.clear)
                        .frame(height: 8)
                        .recessed(radius: 4)

                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * fraction), height: 8)
                        .activeGlow(tint, on: dragging, radius: 5)

                    Circle()
                        .fill(Theme.groundLift)
                        .frame(width: knob, height: knob)
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                        )
                        .shadow(color: Theme.lightEdge, radius: 3, x: -2, y: -2)
                        .shadow(color: Theme.darkEdge, radius: dragging ? 6 : 4, x: 2, y: 3)
                        .offset(x: (w - knob) * fraction)
                }
                .frame(height: 22)
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
            .frame(height: 22)

            if ticks > 1 {
                HStack(spacing: 0) {
                    ForEach(0..<ticks, id: \.self) { i in
                        Circle()
                            .fill(Theme.textFaint.opacity(0.55))
                            .frame(width: 2.5, height: 2.5)
                        if i < ticks - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .animation(Theme.press, value: dragging)
    }
}

/// One wide band of colour. The gradient is the track, so there is nothing to
/// read off a second strip — the control and its meaning are the same object.
struct HueBand: View {
    @Binding var hue: Double          // 0…255, as the firmware stores it
    var saturation: Double = 1
    var onCommit: (() -> Void)?

    @State private var dragging = false

    private var fraction: Double { min(1, max(0, hue / 255)) }
    private var current: Color { Color(hue: fraction, saturation: saturation, brightness: 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = dragging ? 26 : 23

            ZStack(alignment: .leading) {
                LinearGradient(colors: (0...24).map {
                    Color(hue: Double($0) / 24, saturation: saturation, brightness: 1)
                }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 26)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)

                Circle()
                    .fill(current)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.5), radius: dragging ? 5 : 3, y: 1)
                    .offset(x: (w - knob) * fraction)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let usable = max(1, w - knob)
                        hue = min(255, max(0, (g.location.x - knob / 2) / usable * 255))
                    }
                    .onEnded { _ in
                        dragging = false
                        onCommit?()
                    }
            )
        }
        .frame(height: 30)
        .animation(Theme.press, value: dragging)
    }
}

// MARK: - Texture

/// A halftone dot field, drawn rather than shipped as an image so it scales and
/// tints with whatever it sits on. Used sparingly — it is a surface treatment,
/// not decoration.
struct DotField: View {
    var spacing: CGFloat = 5
    var radius: CGFloat = 1
    var color: Color = .white
    var opacity: Double = 0.16

    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.translateBy(x: x, y: y)
                    context.fill(dot, with: .color(color.opacity(opacity)))
                    context.translateBy(x: -x, y: -y)
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A tile that looks like the thing it selects, so the list of effects can be
/// read at a glance instead of word by word.
struct EffectTile: View {
    let title: String
    let mode: Int
    let selected: Bool
    /// The colour the effect is currently set to run in, or nil for the palette.
    var colour: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                preview
                if mode == 5 {
                    DotField(spacing: 6, radius: 1.1, color: .white, opacity: 0.22)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(9)
            }
            .frame(height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.85) : Color.white.opacity(hovering ? 0.2 : 0.09),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: selected ? (colour ?? Theme.accent).opacity(0.35) : .black.opacity(0.3),
                    radius: selected ? 9 : 4, y: 2)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }

    private var band: [Color] {
        if let colour { return [colour, colour] }
        return (0...6).map { Color(hue: Double($0) / 6, saturation: 0.8, brightness: 1) }
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case 0:
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)],
                           startPoint: .top, endPoint: .bottom)
        case 1:
            LinearGradient(colors: band, startPoint: .leading, endPoint: .trailing)
        case 2:
            LinearGradient(colors: [(colour ?? .purple).opacity(0.12), colour ?? .purple],
                           startPoint: .bottom, endPoint: .top)
        case 3:
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    (i.isMultiple(of: 2) ? (colour ?? Color.indigo) : Color(white: 0.10))
                }
            }
        case 4:
            LinearGradient(colors: band + band.reversed(),
                           startPoint: .leading, endPoint: .trailing)
        default:
            LinearGradient(colors: [Color(red: 0.32, green: 0.22, blue: 0.62),
                                    Color(red: 0.62, green: 0.26, blue: 0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Dot matrix numerals

/// Numbers drawn as a dot field rather than set in a typeface.
///
/// A count is a readout from a device, not prose, and drawing it the way an
/// instrument would keeps it from being mistaken for interface text.
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
            for character in text {
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
