import AppKit
import Combine
import SwiftUI
import MacroPadCore

enum EditorTab: String, CaseIterable, Identifiable {
    case keys, media, mouse, led
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keys: return "Keys"
        case .media: return "Media"
        case .mouse: return "Mouse"
        case .led: return "LED"
        }
    }
    var icon: String {
        switch self {
        case .keys: return "keyboard"
        case .media: return "play.circle"
        case .mouse: return "computermouse"
        case .led: return "lightbulb"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {

    // MARK: Device

    @Published private(set) var candidates: [PadCandidate] = []
    @Published var selectedCandidateID: String?
    @Published private(set) var isConnected = false
    @Published var showAllInterfaces = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var statusIsError = false

    // MARK: Transport settings

    @Published var protocolOverride: PadProtocol?
    @Published var reportId: UInt8 = 0
    @Published var channel: ReportChannel = .output
    @Published var mediaEncoding: MediaEncoding = .auto

    // MARK: Configuration

    @Published var layout: KeyboardLayout = LayoutLibrary.default {
        didSet { if layer >= layout.layerCount { layer = 0 } }
    }
    @Published var layer: UInt8 = 0 { didSet { loadEditor() } }
    @Published var selectedAction: InputAction = .key1 { didSet { loadEditor() } }
    @Published var profile = Profile()

    // MARK: Saved profiles

    @Published private(set) var profiles: [ProfileStore.Entry] = []
    @Published var activeProfileName: String?
    private let profileStore = ProfileStore()

    // MARK: Editor state

    @Published var editorTab: EditorTab = .keys
    @Published var sequence: [KeyStroke] = []
    @Published var delay: UInt16 = 0
    @Published var mediaKey: MediaKey = MediaKey.all[0]
    @Published var mouseButton: MouseButton = .left
    @Published var mouseModifiers: Modifier = .none
    @Published var isRecording = false { didSet { isRecording ? startRecording() : stopRecording() } }

    // MARK: Log

    @Published private(set) var log: [HIDLogEntry] = []

    private let transport = PadTransport()
    private var recorderMonitor: Any?

    var visibleCandidates: [PadCandidate] {
        showAllInterfaces ? candidates : candidates.filter(\.isLikelyPad)
    }

    var selectedCandidate: PadCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    /// Protocol actually used for composing: explicit override, else the
    /// known-device table, else Extended (what most current devices speak).
    var activeProtocol: PadProtocol {
        protocolOverride ?? selectedCandidate?.knownProtocol ?? .extended
    }

    var composer: ReportComposer {
        ComposerFactory.make(activeProtocol, reportId: reportId, mediaEncoding: mediaEncoding)
    }

    /// Keystrokes one mapping can hold, given both the device layout and what
    /// the protocol itself can express.
    var maxKeystrokes: Int {
        min(layout.maxCharacters, activeProtocol.maxKeystrokesPerControl)
    }

    /// Which editors this protocol can actually write. Showing a control that
    /// silently does nothing is worse than saying it is not supported yet.
    func supports(_ tab: EditorTab) -> Bool {
        guard activeProtocol == .webHub else { return true }
        switch tab {
        case .keys, .media: return true
        case .mouse, .led: return false
        }
    }

    var unsupportedNote: String? {
        guard activeProtocol == .webHub, !supports(editorTab) else { return nil }
        return editorTab == .mouse
            ? "Mouse actions are not supported on this device yet — its encoding for them has not been worked out, and writing a guess would corrupt the key table."
            : "Backlight is not supported on this device yet — it uses a separate command set that has not been worked out."
    }

    init() {
        transport.onDeviceListChanged = { [weak self] in
            Task { @MainActor in self?.deviceListChanged() }
        }
        transport.onLog = { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
        transport.startMonitoring()
        deviceListChanged()
        refreshProfiles()
        loadEditor()
    }

    // MARK: - Device handling

    private func deviceListChanged() {
        candidates = transport.candidates
        isConnected = transport.isOpen
        if selectedCandidate == nil {
            selectedCandidateID = transport.bestCandidate?.id
            adoptLayoutForSelection()
        }
        if !isConnected && transport.openedCandidate == nil && status.hasPrefix("Connected") {
            setStatus("Device disconnected", error: true)
        }
    }

    private func adoptLayoutForSelection() {
        guard let c = selectedCandidate else { return }
        if let match = LayoutLibrary.best(forVendorId: c.vendorId, productId: c.productId) {
            layout = match
        }
    }

    func refreshDevices() {
        transport.refresh()
        deviceListChanged()
    }

    func connect() {
        guard let candidate = selectedCandidate ?? transport.bestCandidate else {
            setStatus("No macro pad found", error: true)
            return
        }
        selectedCandidateID = candidate.id
        switch transport.open(candidate) {
        case .success:
            isConnected = true
            adoptLayoutForSelection()
            setStatus("Connected — \(candidate.displayName), \(activeProtocol.displayName), report id \(reportId)")
        case .failure(let error):
            isConnected = false
            setStatus(error.localizedDescription, error: true)
        }
    }

    func disconnect() {
        transport.close()
        isConnected = false
        setStatus("Not connected")
    }

    // MARK: - Editor <-> profile

    var currentBinding: ControlBinding {
        profile[layer, selectedAction]
    }

    private func loadEditor() {
        switch currentBinding {
        case .unset:
            sequence = []
            delay = 0
            editorTab = .keys
        case .keys(let seq, let d):
            sequence = seq
            delay = d
            editorTab = .keys
        case .media(let key):
            mediaKey = key
            editorTab = .media
        case .mouse(let button, let mods):
            mouseButton = button
            mouseModifiers = mods
            editorTab = .mouse
        }
    }

    /// Writes the editor state back into the profile for the selected control.
    func commit() {
        switch editorTab {
        case .keys:
            profile[layer, selectedAction] = sequence.isEmpty ? .unset : .keys(sequence: sequence, delay: delay)
        case .media:
            profile[layer, selectedAction] = .media(mediaKey)
        case .mouse:
            profile[layer, selectedAction] = .mouse(button: mouseButton, modifiers: mouseModifiers)
        case .led:
            break   // LED is device-wide, not per control
        }
    }

    func clearBinding() {
        sequence = []
        delay = 0
        profile[layer, selectedAction] = .unset
    }

    func binding(for action: InputAction) -> ControlBinding {
        profile[layer, action]
    }

    // MARK: - Recording

    private func startRecording() {
        guard recorderMonitor == nil else { return }
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            self.record(event)
            return nil   // swallow the key so it doesn't reach the UI
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m) }
        recorderMonitor = nil
    }

    private func record(_ event: NSEvent) {
        guard sequence.count < maxKeystrokes else {
            setStatus(maxKeystrokes == 1
                      ? "This device stores one keystroke per key — clear it to record a different one"
                      : "This device holds at most \(maxKeystrokes) keystrokes", error: true)
            return
        }
        guard let usage = HIDKeyboard.virtualKeyToUsage[event.keyCode] else { return }

        var mods = HIDKeyboard.modifiers(from: event.modifierFlags.rawValue)
        if mods.isEmpty {
            // Fall back to the layout-independent flags if the device-specific
            // bits are missing (some synthetic events don't carry them).
            let f = event.modifierFlags
            if f.contains(.control) { mods.insert(.leftCtrl) }
            if f.contains(.shift) { mods.insert(.leftShift) }
            if f.contains(.option) { mods.insert(.leftAlt) }
            if f.contains(.command) { mods.insert(.leftGui) }
        }

        sequence.append(KeyStroke(usage: usage, modifiers: mods))
        editorTab = .keys
        commit()
    }

    func addKey(usage: UInt8, modifiers: Modifier) {
        guard sequence.count < maxKeystrokes else { return }
        sequence.append(KeyStroke(usage: usage, modifiers: modifiers))
        commit()
    }

    func removeLastKey() {
        guard !sequence.isEmpty else { return }
        sequence.removeLast()
        commit()
    }

    // MARK: - Upload

    func uploadSelected() {
        isRecording = false
        guard ensureConnected() else { return }
        commit()

        let reports: [PadReport]
        if editorTab == .led {
            reports = composer.led(layer: layer, mode: profile.ledMode, color: profile.ledColor)
            if reports.isEmpty {
                setStatus("This firmware only supports LED modes 0–2", error: true)
                return
            }
        } else {
            guard selectedAction != .none else {
                setStatus("Select a key or knob action first", error: true)
                return
            }
            if let note = unsupportedNote {
                setStatus(note, error: true)
                return
            }
            if case .unset = currentBinding, let webhub = composer as? WebHubComposer {
                // "Nothing" is a real state on this protocol: write the disabled entry.
                reports = webhub.clear(action: selectedAction, layer: layer)
            } else {
                reports = composer.reports(for: currentBinding, action: selectedAction, layer: layer)
            }
            if reports.isEmpty {
                setStatus("Nothing mapped to \(selectedAction.displayName)", error: true)
                return
            }
        }
        send(reports, describing: editorTab == .led ? "LED settings" : selectedAction.displayName)
    }

    func uploadAll() {
        isRecording = false
        guard ensureConnected() else { return }
        commit()

        var reports: [PadReport] = []
        for entry in profile.configured(layerCount: layout.layerCount) {
            reports.append(contentsOf: composer.reports(for: entry.binding, action: entry.action, layer: entry.layer))
        }
        reports.append(contentsOf: composer.led(layer: layer, mode: profile.ledMode, color: profile.ledColor))
        guard !reports.isEmpty else {
            setStatus("Nothing to upload — no mappings configured", error: true)
            return
        }
        send(reports, describing: "\(profile.configured(layerCount: layout.layerCount).count) mapping(s)")
    }

    private func ensureConnected() -> Bool {
        if isConnected { return true }
        connect()
        return isConnected
    }

    private func send(_ reports: [PadReport], describing what: String) {
        for report in reports {
            if case .failure(let error) = transport.write(report, channel: channel) {
                setStatus("Upload failed: \(error.localizedDescription)", error: true)
                return
            }
            // The firmware drops frames that arrive back to back.
            usleep(15_000)
        }
        setStatus("Uploaded \(what) — \(reports.count) report(s)")
    }

    /// Sends a zero frame on each report id to see which ones the device takes.
    func probeReportIds() {
        guard ensureConnected() else { return }
        let accepted = ReportChannel.allCases.flatMap { ch in
            ([0, 2, 3] as [UInt8]).compactMap { id -> String? in
                if case .success = transport.write(ComposerFactory.versionProbe(reportId: id), channel: ch) {
                    return "\(ch.rawValue) id \(id)"
                }
                return nil
            }
        }
        setStatus(accepted.isEmpty ? "No report id accepted" : "Accepted: \(accepted.joined(separator: ", "))",
                  error: accepted.isEmpty)
    }

    // MARK: - Saved profiles

    func refreshProfiles() {
        profiles = profileStore.list()
    }

    /// Loads a saved profile and, when a pad is connected, pushes it straight to
    /// the hardware — switching profiles is the whole point of having them.
    func switchTo(_ entry: ProfileStore.Entry) {
        do {
            let loaded = try profileStore.load(entry)
            profile = loaded
            activeProfileName = entry.name
            if let match = LayoutLibrary.all.first(where: { $0.name == loaded.layoutName }) { layout = match }
            loadEditor()
            if isConnected {
                uploadAll()
            } else {
                setStatus("Loaded “\(entry.name)” — connect the pad to apply it")
            }
        } catch {
            setStatus("Could not open “\(entry.name)”: \(error.localizedDescription)", error: true)
        }
    }

    func saveProfile(named name: String) {
        commit()
        var p = profile
        p.layoutName = layout.name
        do {
            let entry = try profileStore.save(p, as: name)
            profile.name = name
            activeProfileName = entry.name
            refreshProfiles()
            setStatus("Saved “\(entry.name)”")
        } catch {
            setStatus("Could not save: \(error.localizedDescription)", error: true)
        }
    }

    func deleteProfile(_ entry: ProfileStore.Entry) {
        do {
            try profileStore.delete(entry)
            if activeProfileName == entry.name { activeProfileName = nil }
            refreshProfiles()
            setStatus("Deleted “\(entry.name)”")
        } catch {
            setStatus("Could not delete: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Status & log

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func append(_ entry: HIDLogEntry) {
        log.append(entry)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func clearLog() { log.removeAll() }
}
