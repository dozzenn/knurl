import AppKit

/// Keeps the window reachable.
///
/// A menu bar item keeps the app alive after its window is closed, so clicking
/// the app again finds it already running and macOS simply activates it —
/// leaving the user staring at nothing. These two hooks make "open the app"
/// mean "show me the window" in every case: a fresh launch, a relaunch while it
/// is already running, and a click on the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // After the scene has had a chance to build its window.
        DispatchQueue.main.async { AppDelegate.showMainWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.showMainWindow()
        return true
    }

    /// The window scene keeps its window around when it is closed, so it only
    /// needs ordering front again.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let candidates = NSApp.windows.filter {
            $0.canBecomeMain && !($0 is NSPanel)
        }
        let window = candidates.first { $0.isVisible } ?? candidates.first
        window?.makeKeyAndOrderFront(nil)
    }
}
