import AppKit
import SwiftUI
import MacroPadCore

/// One thing the palette can do.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var icon: String
    var group: String
    var keys: [String] = []
    let run: () -> Void
}

// MARK: - Panel

/// A floating, keyboard-driven command window. Kept in AppKit rather than a
/// SwiftUI `Window` scene because it has to be borderless, float above other
/// apps, and close the moment focus leaves it.
@MainActor
final class PaletteController {
    static let shared = PaletteController()

    private var panel: NSPanel?
    private var monitor: Any?
    private weak var model: AppModel?

    func attach(_ model: AppModel) { self.model = model }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard let model else { return }
        if panel == nil { panel = makePanel(for: model) }
        guard let panel else { return }

        // Centre horizontally, and high enough that the list grows downward
        // into empty screen rather than off the bottom.
        if let screen = NSScreen.main {
            let size = panel.frame.size
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY + frame.height * 0.14 - size.height / 2
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        removeMonitor()
    }

    private func makePanel(for model: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let root = PaletteView(model: model, onClose: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        panel.contentView = host
        return panel
    }

    // Arrow keys and Return belong to the list, not to the text field, so they
    // are taken before the field sees them.
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isOpen else { return event }
            switch event.keyCode {
            case 53:                       // esc
                self.close(); return nil
            case 125:                      // down
                PaletteSelection.shared.move(1); return nil
            case 126:                      // up
                PaletteSelection.shared.move(-1); return nil
            case 36, 76:                   // return / keypad enter
                PaletteSelection.shared.activate(); return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Shared cursor state, so the AppKit key monitor and the SwiftUI list agree on
/// which row is highlighted.
@MainActor
final class PaletteSelection: ObservableObject {
    static let shared = PaletteSelection()
    @Published var index = 0
    var count = 0
    var onActivate: (() -> Void)?

    func move(_ delta: Int) {
        guard count > 0 else { return }
        index = max(0, min(count - 1, index + delta))
    }
    func activate() { onActivate?() }
    func reset() { index = 0 }
}

// MARK: - View

private struct PaletteView: View {
    @ObservedObject var model: AppModel
    @StateObject private var selection = PaletteSelection.shared
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [PaletteCommand] {
        let all = model.paletteCommands
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.title.lowercased().contains(q)
                || ($0.subtitle?.lowercased().contains(q) ?? false)
                || $0.group.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Hairline()

            if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: "No matches",
                               message: "Try a profile name, or “save”.")
                    .frame(height: 180)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(grouped.enumerated()), id: \.offset) { _, section in
                                SectionLabel(text: section.name)
                                ForEach(section.items, id: \.offset) { item in
                                    Row(title: item.command.title,
                                        subtitle: item.command.subtitle,
                                        icon: item.command.icon,
                                        selected: item.offset == selection.index,
                                        action: { activate(item.command) }) {
                                        if item.offset == selection.index {
                                            ShortcutHint(keys: ["↵"], emphasized: true)
                                        } else if !item.command.keys.isEmpty {
                                            ShortcutHint(keys: item.command.keys)
                                        }
                                    }
                                    .id(item.offset)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection.index) { i in proxy.scrollTo(i, anchor: .center) }
                }
            }

            Hairline()
            footer
        }
        .background(PopoverBackground())
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            searchFocused = true
            selection.reset()
            syncSelection()
        }
        .onChange(of: query) { _ in
            selection.reset()
            syncSelection()
        }
        .onChange(of: results.count) { _ in syncSelection() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textFaint)
            TextField("Switch profile, save to keypad…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onSubmit { activateSelected() }
            if model.isConnected {
                HStack(spacing: 6) {
                    StatusDot(color: Theme.online)
                    Text(model.deviceLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            Text("MacroPad")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textFaint)
            Spacer()
            Text("Run")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            ShortcutHint(keys: ["↵"])
            Text("Close")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            ShortcutHint(keys: ["esc"])
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private struct Section { let name: String; let items: [(offset: Int, command: PaletteCommand)] }

    /// Flat index across sections, so arrow keys walk the whole list.
    private var grouped: [Section] {
        var out: [Section] = []
        var offset = 0
        for name in orderedGroups {
            let items = results.filter { $0.group == name }
            guard !items.isEmpty else { continue }
            out.append(Section(name: name, items: items.map { c in
                defer { offset += 1 }
                return (offset, c)
            }))
        }
        return out
    }

    private var orderedGroups: [String] {
        var seen: [String] = []
        for c in results where !seen.contains(c.group) { seen.append(c.group) }
        return seen
    }

    private var flat: [PaletteCommand] { grouped.flatMap { $0.items.map(\.command) } }

    private func syncSelection() {
        selection.count = flat.count
        selection.index = min(selection.index, max(0, flat.count - 1))
        selection.onActivate = { activateSelected() }
    }

    private func activateSelected() {
        guard flat.indices.contains(selection.index) else { return }
        activate(flat[selection.index])
    }

    private func activate(_ command: PaletteCommand) {
        onClose()
        command.run()
    }
}
