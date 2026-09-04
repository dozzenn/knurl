import AppKit
import SwiftUI

/// Reports mouse enter and exit through an `NSTrackingArea`.
///
/// SwiftUI's own hover modifiers do not fire reliably inside a menu bar
/// window — the panel does not deliver mouse-moved events the way an ordinary
/// window does — so hover feedback there has to come from AppKit directly.
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(new)
            area = new
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}

extension View {
    /// Hover that works everywhere the app puts a row, menu bar included.
    func trackingHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: onChange))
    }
}

/// The app's mark: a dot-matrix K sitting on a knob.
///
/// Drawn rather than shipped as an asset so the menu bar can have it as a
/// template image, which is the only way an icon there follows the menu bar's
/// own light or dark appearance.
enum Wordmark {
    /// A 3×5 K, the same grid the readouts use.
    private static let k = ["101", "101", "110", "101", "101"]

    static func menuBarImage(height: CGFloat = 17) -> NSImage {
        let size = NSSize(width: height, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let d = rect.height
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1.2
            NSColor.black.setStroke()
            ring.stroke()

            // Pointer notch at the top, so it reads as something you turn.
            let notch = NSBezierPath(ovalIn: CGRect(x: rect.midX - d * 0.055,
                                                    y: rect.maxY - d * 0.20,
                                                    width: d * 0.11, height: d * 0.11))
            NSColor.black.setFill()
            notch.fill()

            // The K, plotted on the face.
            let dot = d * 0.093
            let pitch = dot * 1.62
            let originX = rect.midX - pitch * 1.5 + (pitch - dot) / 2
            let originY = rect.midY + pitch * 2.5 - pitch
            for (r, row) in k.enumerated() {
                for (c, bit) in row.enumerated() where bit == "1" {
                    let cell = CGRect(x: originX + CGFloat(c) * pitch,
                                      y: originY - CGFloat(r) * pitch,
                                      width: dot, height: dot)
                    NSBezierPath(ovalIn: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
