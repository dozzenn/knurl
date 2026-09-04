import AppKit
import SwiftUI
import KnurlCore

/// Everything the app can do lives in this one window, listed down the left.
/// Settings are a section here rather than a separate window behind a menu —
/// on a control panel you can see every switch at once.
enum PanelSection: String, CaseIterable, Identifiable {
    case keys, backlight, apps, presets, general, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keys: return "Keys"
        case .backlight: return "Backlight"
        case .apps: return "Apps"
        case .presets: return "Presets"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .keys: return "square.grid.2x2.fill"
        case .backlight: return "lightbulb.fill"
        case .apps: return "app.badge.fill"
        case .presets: return "bookmark.fill"
        case .general: return "gearshape.fill"
        case .about: return "info.circle.fill"
        }
    }

    var group: String {
        switch self {
        case .keys, .backlight, .apps, .presets: return "Keypad"
        case .general, .about: return "Knurl"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLog = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $model.section)
            Rectangle().fill(Theme.outline.opacity(0.35)).frame(width: 1)

            VStack(spacing: 0) {
                SectionHeader(section: model.section, showLog: $showLog)
                Hairline()

                Group {
                    switch model.section {
                    case .keys: KeysSection()
                    case .backlight: BacklightSection()
                    case .apps: AppsSection()
                    case .presets: PresetsSection()
                    case .general: GeneralSection()
                    case .about: AboutSection()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showLog {
                    Hairline()
                    LogPane().frame(height: 160)
                }
                Hairline()
                StatusStrip()
            }
        }
        .background(WindowBackground())
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var section: PanelSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DotMatrixNumber(text: "KNURL", dot: 2.5, gap: 1.4, color: Theme.text)
                .padding(.leading, 12)
                .padding(.top, Theme.trafficLightInset - 40)
                .padding(.bottom, 14)

            DevicePlate()
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(["Keypad", "Knurl"], id: \.self) { group in
                PanelLabel(text: group, colour: Theme.textFaint)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                ForEach(PanelSection.allCases.filter { $0.group == group }) { item in
                    NavRow(item: item, selected: section == item) { section = item }
                }
            }

            Spacer()

            // Pinned to the bottom: switching the panel's material is something
            // you reach for, not something you hunt through settings for.
            AppearanceSwitch()
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(width: 208)
    }
}

private struct NavRow: View {
    let item: PanelSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textOnWell : Theme.textMuted)
                    .frame(width: 18)
                Text(item.title.uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(selected ? Theme.textOnWell : Theme.text)
                Spacer(minLength: 0)
                Lamp(on: selected, size: 6)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .modifier(NavRowSurface(selected: selected, hovering: hovering))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct NavRowSurface: ViewModifier {
    let selected: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        if selected {
            content
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(hovering ? Color.black.opacity(0.06) : .clear))
        }
    }
}

/// The device, shown the way a panel shows its connection: a name plate and a lamp.
private struct DevicePlate: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 9) {
                Lamp(on: model.isConnected, colour: Theme.lampGood, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.deviceLabel)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    PanelLabel(text: model.isConnected ? "connected" : "no keypad",
                               colour: Theme.textFaint, size: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .lifted(radius: Theme.radius, depth: 0.8)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .popover(isPresented: $showing, arrowEdge: Edge.trailing) {
            DevicePopover().environmentObject(model)
        }
    }
}

/// Auto, light, dark — three lit buttons in a trough, like a mode selector.
private struct AppearanceSwitch: View {
    @EnvironmentObject private var model: AppModel

    private let options: [(AppModel.Appearance, String, String)] = [
        (.system, "circle.lefthalf.filled", "Follow the system"),
        (.light, "sun.max.fill", "Light"),
        (.dark, "moon.fill", "Dark"),
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { option, icon, help in
                let on = model.appearance == option
                Button { model.appearance = option } label: {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(on ? Theme.textOnWell : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .modifier(AppearanceSegment(on: on))
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .help(help)
            }
        }
        .padding(3)
        .trough(radius: Theme.radiusSmall)
    }
}

private struct AppearanceSegment: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
        } else {
            content.contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

// MARK: - Header

private struct SectionHeader: View {
    @EnvironmentObject private var model: AppModel
    let section: PanelSection
    @Binding var showLog: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(section.title)
                .font(Theme.heading)
                .foregroundStyle(Theme.text)

            Spacer(minLength: 12)

            if section == .keys || section == .backlight {
                PanelButton(title: "Save to keypad", prominent: true) { model.saveToKeyboard() }
            }
            PanelButton(title: "Log", lamp: showLog, compact: true) { showLog.toggle() }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 62)
    }
}

// MARK: - Keys

private struct KeysSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
            .onAppear { model.startLiveWatch() }
            .onDisappear { model.stopLiveWatch() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScopeStrip()
            Hairline()
            HStack(spacing: 0) {
                PadPane().frame(maxWidth: .infinity)
                Rectangle().fill(Theme.outline.opacity(0.3)).frame(width: 1)
                InspectorPane().frame(width: 344)
            }
        }
    }
}

/// Which app the keys below belong to.
struct ScopeStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            PanelLabel(text: "applies to", colour: Theme.textFaint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(model.scopes) { scope in
                        ScopeChip(scope: scope)
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 6)
            PanelButton(title: "Add app", compact: true) { pickApp(model) }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 48)
    }
}

struct ScopeChip: View {
    @EnvironmentObject private var model: AppModel
    let scope: MappingScope

    private var selected: Bool { model.currentScopeKey == scope.key }
    private var isLive: Bool { model.liveScopeKey == scope.key && model.isConnected }

    var body: some View {
        Button { model.selectScope(scope.key) } label: {
            HStack(spacing: 7) {
                if scope.isGlobal {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Theme.textOnWell : Theme.textMuted)
                } else if let icon = appIcon(for: scope.key) {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(scope.name.uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(selected ? Theme.textOnWell : Theme.text)
                    .lineLimit(1)
                Lamp(on: isLive, colour: Theme.lampGood, size: 6)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .modifier(ChipSurface(on: selected))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ChipSurface: ViewModifier {
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

func appIcon(for bundleId: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

@MainActor
func pickApp(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.title = "Choose an app"
    panel.message = "Keys you set for this app apply only while it is in front."
    guard panel.runModal() == .OK, let url = panel.url,
          let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
    let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
        ?? (bundle.infoDictionary?["CFBundleName"] as? String)
        ?? url.deletingPathExtension().lastPathComponent
    model.addAppScope(bundleId: id, name: name)
}

// MARK: - Status strip

private struct StatusStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Lamp(on: true,
                 colour: model.statusIsError ? Theme.lampAlert : Theme.lampOff,
                 size: 7)
            Text(model.status)
                .font(Theme.rowDetail)
                .foregroundStyle(model.statusIsError ? Theme.text : Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            PanelLabel(text: model.activeProtocol.displayName, colour: Theme.textFaint, size: 9)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 34)
    }
}

// MARK: - Device popover

struct DevicePopover: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftNickname = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Keypads")

            if model.visibleCandidates.isEmpty {
                EmptyStateView(icon: "cable.connector.slash",
                               title: "No keypad found",
                               message: "Plug one in — it should appear within a second.")
            }

            ForEach(model.visibleCandidates) { candidate in
                Row(title: model.displayName(for: candidate),
                    subtitle: candidate.detail,
                    icon: "keyboard",
                    selected: candidate.id == model.selectedCandidateID,
                    action: {
                        model.selectedCandidateID = candidate.id
                        model.connect()
                        draftNickname = model.nickname(for: candidate) ?? ""
                    }) {
                    Lamp(on: candidate.id == model.selectedCandidateID,
                         colour: Theme.lampGood, size: 6)
                }
            }

            if let candidate = model.selectedCandidate {
                SectionLabel(text: "Nickname")
                HStack(spacing: 7) {
                    TextField(candidate.product.isEmpty ? "My keypad" : candidate.product,
                              text: $draftNickname)
                        .textFieldStyle(.plain)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.textOnWell)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .well(radius: Theme.radiusSmall)
                        .onSubmit { model.setNickname(draftNickname, for: candidate) }
                    PanelButton(title: "Set", compact: true) {
                        model.setNickname(draftNickname, for: candidate)
                    }
                }
                .padding(.horizontal, 10)
            }

            SectionLabel(text: "Interfaces")
            HStack(spacing: 7) {
                PanelButton(title: "Refresh", compact: true) { model.refreshDevices() }
                PanelButton(title: model.isConnected ? "Disconnect" : "Connect", compact: true) {
                    model.isConnected ? model.disconnect() : model.connect()
                }
                Spacer()
                Toggle("", isOn: $model.showAllInterfaces)
                    .toggleStyle(.checkbox)
                PanelLabel(text: "show all", colour: Theme.textFaint, size: 9)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .padding(.vertical, 6)
        .frame(width: 330)
        .background(PopoverBackground())
    }
}

// MARK: - Log

private struct LogPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PanelLabel(text: "HID traffic", colour: Theme.textFaint)
                Spacer()
                Readout(text: "\(model.log.count)")
                PanelButton(title: "Clear", compact: true) { model.clearLog() }
            }
            .padding(.horizontal, Theme.gutter)
            .frame(height: 32)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.log) { entry in
                            HStack(alignment: .top, spacing: 7) {
                                Text(entry.outgoing ? "→" : "←")
                                    .foregroundStyle(entry.ok
                                                     ? (entry.outgoing ? Theme.lampOn : Theme.lampGood)
                                                     : Theme.lampAlert)
                                Text(entry.text)
                                    .foregroundStyle(Theme.textOnWellMuted)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: model.log.count) { _ in
                    if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .well(radius: Theme.radiusSmall)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
    }
}
