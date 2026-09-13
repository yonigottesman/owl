import AppKit

@main
enum IconBuilder {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Owl.iconset")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let image = NSImage(size: NSSize(width: pixels, height: pixels), flipped: false) { rect in
                    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04), xRadius: rect.width * 0.22, yRadius: rect.height * 0.22).fill()
                    OwlIcon.image(active: true, size: CGFloat(pixels)).draw(in: rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16))
                    return true
                }
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                let suffix = scale == 2 ? "@2x" : ""
                try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
