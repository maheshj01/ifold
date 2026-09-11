import AppKit

/// The brand mark (brand/ifold-mark-mono-filled.svg) as a template image for
/// the menu bar: a landscape screen whose bottom-right corner folds. Drawn
/// with paths so it needs no asset catalog and stays crisp on any display.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            let s = 18.0 / 32.0 // the SVG is on a 32-unit grid
            let t = NSAffineTransform(); t.scale(by: s)

            // Screen minus the corner that folds (bottom-right, hinge side).
            let screen = NSBezierPath()
            screen.move(to: NSPoint(x: 5, y: 7))
            screen.line(to: NSPoint(x: 25, y: 7))
            screen.appendArc(from: NSPoint(x: 28, y: 7), to: NSPoint(x: 28, y: 10), radius: 3)
            screen.line(to: NSPoint(x: 28, y: 16.2))
            screen.line(to: NSPoint(x: 18.2, y: 26))
            screen.line(to: NSPoint(x: 5, y: 26))
            screen.appendArc(from: NSPoint(x: 2, y: 26), to: NSPoint(x: 2, y: 23), radius: 3)
            screen.line(to: NSPoint(x: 2, y: 10))
            screen.appendArc(from: NSPoint(x: 2, y: 7), to: NSPoint(x: 5, y: 7), radius: 3)
            screen.close()

            // The folded corner: the back of the screen, lighter.
            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: 28, y: 18.6))
            corner.line(to: NSPoint(x: 28, y: 23))
            corner.appendArc(from: NSPoint(x: 28, y: 26), to: NSPoint(x: 25, y: 26), radius: 3)
            corner.line(to: NSPoint(x: 20.6, y: 26))
            corner.close()

            screen.transform(using: t as AffineTransform); corner.transform(using: t as AffineTransform)
            NSColor.black.setFill(); screen.fill()
            NSColor.black.withAlphaComponent(0.55).setFill(); corner.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
