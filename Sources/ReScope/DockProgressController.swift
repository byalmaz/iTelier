import AppKit

/// Only the app's Dock tile is customised; the underlying app icon is preserved.
@MainActor
final class DockProgressController {
    private let view = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private var timer: Timer?
    private var installed = false
    func update(active: Bool, fraction: Double?, paused: Bool) {
        guard active else {
            timer?.invalidate(); timer = nil
            if installed { NSApp.dockTile.contentView = nil; NSApp.dockTile.badgeLabel = nil; NSApp.dockTile.display(); installed = false }
            return
        }
        if !installed {
            view.icon = NSApp.applicationIconImage
            NSApp.dockTile.contentView = view; installed = true
        }
        view.fraction = fraction.map { min(1, max(0, $0)) }; view.paused = paused
        NSApp.dockTile.badgeLabel = paused ? "Ⅱ" : fraction.map { "\(Int(min(1, max(0, $0)) * 100))%" }
        if fraction == nil && !paused && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if timer == nil {
                timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.view.angle = (self.view.angle + 12).truncatingRemainder(dividingBy: 360)
                        self.redraw()
                    }
                }
                RunLoop.main.add(timer!, forMode: .common)
            }
        } else { timer?.invalidate(); timer = nil }
        redraw()
    }
    private func redraw() { view.needsDisplay = true; NSApp.dockTile.display() }
    deinit { timer?.invalidate() }
}
private final class DockProgressView: NSView {
    var icon: NSImage?
    var fraction: Double?
    var paused = false
    var angle: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        icon?.draw(in: bounds.insetBy(dx: 3, dy: 3))
        let rect = bounds.insetBy(dx: 10, dy: 10)
        NSColor.black.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 25, yRadius: 25).fill()
        let centre = NSPoint(x: bounds.midX, y: bounds.midY), radius = bounds.width * 0.32
        let track = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = 8; NSColor.white.withAlphaComponent(0.3).setStroke(); track.stroke()
        let arc = NSBezierPath(); arc.lineWidth = 8; arc.lineCapStyle = .round
        let start: CGFloat = fraction == nil ? 90 - angle : 90
        arc.appendArc(withCenter: centre, radius: radius, startAngle: start, endAngle: start - CGFloat(fraction ?? 0.24) * 359.9, clockwise: true)
        NSColor(srgbRed: 0.26, green: 0.84, blue: 0.95, alpha: 1).setStroke(); arc.stroke()
        if paused {
            NSColor.white.setFill()
            for x in [centre.x - 11, centre.x + 5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: centre.y - 14, width: 6, height: 28), xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
