import AppKit

enum OwlIcon {
    static let amber = NSColor(srgbRed: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255, alpha: 1)

    static func image(active: Bool, size: CGFloat = 22) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: rect.width / 24, y: rect.height / 24)
            context.translateBy(x: 0, y: 24)
            context.scaleBy(x: 1, y: -1)
            let color = (active ? amber : NSColor.black).cgColor
            context.setFillColor(color)

            // The selected D · Perched silhouette, on the preview's 24-point grid.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 5, y: 2))
            body.addLine(to: CGPoint(x: 9, y: 5))
            body.addQuadCurve(to: CGPoint(x: 15, y: 5), control: CGPoint(x: 12, y: 4))
            body.addLine(to: CGPoint(x: 19, y: 2))
            body.addLine(to: CGPoint(x: 19, y: 9))
            body.addQuadCurve(to: CGPoint(x: 20, y: 18), control: CGPoint(x: 22, y: 13))
            body.addLine(to: CGPoint(x: 17, y: 20))
            body.addLine(to: CGPoint(x: 7, y: 20))
            body.addLine(to: CGPoint(x: 4, y: 18))
            body.addQuadCurve(to: CGPoint(x: 5, y: 9), control: CGPoint(x: 2, y: 13))
            body.closeSubpath()
            context.addPath(body); context.fillPath()

            // Transparent facial details adapt to both menu-bar appearances.
            context.setBlendMode(.destinationOut)
            context.setFillColor(NSColor.black.cgColor)
            for x in [8.5, 15.5] {
                context.fillEllipse(in: CGRect(x: x - 2.6, y: 6.4, width: 5.2, height: 5.2))
            }
            context.move(to: CGPoint(x: 10.5, y: 13))
            context.addLine(to: CGPoint(x: 12, y: 15))
            context.addLine(to: CGPoint(x: 13.5, y: 13))
            context.closePath(); context.fillPath()
            context.setBlendMode(.normal)
            context.setFillColor(color)
            for x in [9.0, 15.0] {
                context.fillEllipse(in: CGRect(x: x - 0.9, y: 8.1, width: 1.8, height: 1.8))
            }
            context.setStrokeColor(color)
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            for x in [8.0, 16.0] {
                context.move(to: CGPoint(x: x, y: 20))
                context.addLine(to: CGPoint(x: x, y: 22))
            }
            context.move(to: CGPoint(x: 3, y: 22))
            context.addLine(to: CGPoint(x: 21, y: 22))
            context.strokePath()
            return true
        }
        image.isTemplate = !active
        image.accessibilityDescription = active ? "Owl — keeping Mac awake" : "Owl — normal sleep"
        return image
    }
}
