import AppKit
import SwiftUI

// The visual language: one dark translucent surface, a tight type scale, dense
// rows, and motion reserved for things a pointer does. Anything reachable from
// the keyboard is deliberately instant — this app is used in short bursts and
// animation on a repeated action reads as lag.

enum Theme {

    // MARK: Colour
    //
    // Everything is white at a given opacity so the single translucent surface
    // underneath stays visible through the whole hierarchy. Stacking a second
    // translucent layer would wash the text out, so nested surfaces are opaque
    // tints instead.

    static let text        = Color.white.opacity(0.93)
    static let textMuted   = Color.white.opacity(0.56)
    static let textFaint   = Color.white.opacity(0.34)

    static let hairline    = Color.white.opacity(0.075)
    static let rowHover    = Color.white.opacity(0.055)
    static let rowSelected = Color.white.opacity(0.10)
    static let fill        = Color.white.opacity(0.07)
    static let fillStrong  = Color.white.opacity(0.12)

    static let accent      = Color(red: 1.00, green: 0.39, blue: 0.39)   // signal red
    static let online      = Color(red: 0.20, green: 0.84, blue: 0.29)
    static let warning     = Color(red: 1.00, green: 0.72, blue: 0.30)

    /// Sits behind the blurred material so the window keeps its weight over a
    /// bright desktop.
    static let scrim       = Color.black.opacity(0.34)

    // MARK: Metrics

    static let windowRadius: CGFloat = 12
    static let radius: CGFloat = 7
    static let radiusSmall: CGFloat = 5
    static let rowHeight: CGFloat = 34
    static let barHeight: CGFloat = 44
    static let gutter: CGFloat = 12
    /// Room for the traffic lights when the title bar is hidden.
    static let trafficLightInset: CGFloat = 76

    // MARK: Type
    //
    // Tracking is set per size rather than once globally: large text reads too
    // loose without negative tracking, small caps text too tight without a
    // positive nudge.

    static let rowTitle    = Font.system(size: 13, weight: .medium)
    static let rowSubtitle = Font.system(size: 11, weight: .regular)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let caption     = Font.system(size: 11, weight: .regular)
    static let keycap      = Font.system(size: 10.5, weight: .medium, design: .rounded)
    static let mono        = Font.system(size: 10.5, weight: .regular, design: .monospaced)

    // MARK: Motion

    /// Pointer-driven feedback only. Keyboard actions stay instant.
    static let hover  = Animation.easeOut(duration: 0.12)
    static let press  = Animation.easeOut(duration: 0.13)
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
        WindowSurface()
            .overlay(Theme.scrim)
            .ignoresSafeArea()
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
            .frame(minWidth: 18)
            .frame(height: 18)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(emphasized ? Theme.fillStrong : Theme.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
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
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.fillStrong
                          : (prominent ? Theme.fill : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(prominent ? Theme.hairline : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// A hoverable bar control that also carries a shortcut hint, the way Raycast
/// labels its primary action.
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
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(isOn ? Theme.fillStrong : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
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
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? Theme.fillStrong : (hovering ? Theme.rowHover : Theme.fill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(active ? Color.white.opacity(0.18) : Theme.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.985))
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

/// Popovers get their own opaque ground: the window is already one translucent
/// layer, and stacking a second one washes the text out.
struct PopoverBackground: View {
    var body: some View {
        Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1))
            .overlay(Color.white.opacity(0.03))
            .ignoresSafeArea()
    }
}
