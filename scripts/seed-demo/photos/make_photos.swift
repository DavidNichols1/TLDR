// Draws the demo seed's two made-up photos (no people), full size and the
// app's small copy, as JPEGs next to this file:
//   door-note.jpg / door-note_small.jpg   Maya's photo of the cabin door code
//   pickles.jpg / pickles_small.jpg       Theo's dog, asleep upside down
//   swift scripts/seed-demo/photos/make_photos.swift
// The app sends 2048 px and 768 px copies; these are 1536 and 768 wide.

import AppKit

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws at 1536 x 1152 pixels (scale 1), then saves the full and small copies.
func save(_ name: String, draw: () -> Void) {
    let size = NSSize(width: 1536, height: 1152)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1536, pixelsHigh: 1152, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    for (suffix, width, quality) in [("", 1536, 0.8), ("_small", 768, 0.72)] {
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width * 3 / 4,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        small.size = NSSize(width: width, height: width * 3 / 4)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: width * 3 / 4))
        NSGraphicsContext.restoreGraphicsState()
        let jpeg = small.representation(using: .jpeg, properties: [.compressionFactor: quality])!
        try! jpeg.write(to: folder.appendingPathComponent("\(name)\(suffix).jpg"))
        print("\(name)\(suffix).jpg  \(width) x \(width * 3 / 4)  \(jpeg.count / 1024) KB")
    }
}

func text(_ s: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    s.draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                      .foregroundColor: ink, .paragraphStyle: style])
}

// Maya: a sticky note on the cabin door, next to the keypad.
save("door-note") {
    color(0x74452A).setFill(); NSRect(x: 0, y: 0, width: 1536, height: 1152).fill()
    color(0x613A22).setFill()
    for x in stride(from: 0.0, to: 1536, by: 192) { NSRect(x: x, y: 0, width: 12, height: 1152).fill() }
    color(0x2E2E33).setFill()
    NSBezierPath(roundedRect: NSRect(x: 1080, y: 300, width: 300, height: 460), xRadius: 28, yRadius: 28).fill()
    color(0xD9D9D1).setFill()
    for row in 0..<4 { for col in 0..<3 {
        NSBezierPath(ovalIn: NSRect(x: 1120 + col * 84, y: 350 + row * 96, width: 60, height: 60)).fill()
    } }
    color(0xF3B33D).setFill()
    let note = NSRect(x: 220, y: 340, width: 640, height: 520)
    NSBezierPath(rect: note).fill()
    let ink = color(0x2A1E19)
    text("cabin door code", in: NSRect(x: note.minX, y: 720, width: note.width, height: 84), size: 60, weight: .medium, ink: ink)
    text("4471", in: NSRect(x: note.minX, y: 510, width: note.width, height: 240), size: 176, weight: .bold, ink: ink)
    text("hit # after", in: NSRect(x: note.minX, y: 410, width: note.width, height: 72), size: 52, weight: .regular, ink: ink)
}

// Theo: Pickles asleep upside down on the couch.
save("pickles") {
    color(0xE9DFCF).setFill(); NSRect(x: 0, y: 0, width: 1536, height: 1152).fill()       // wall
    color(0x8C6A4F).setFill(); NSRect(x: 0, y: 0, width: 1536, height: 220).fill()        // floor
    color(0x1E6E6A).setFill()                                                            // couch
    NSBezierPath(roundedRect: NSRect(x: 140, y: 200, width: 1256, height: 300), xRadius: 40, yRadius: 40).fill()
    NSBezierPath(roundedRect: NSRect(x: 140, y: 440, width: 1256, height: 360), xRadius: 60, yRadius: 60).fill()
    color(0x175753).setFill()
    NSBezierPath(roundedRect: NSRect(x: 80, y: 200, width: 180, height: 420), xRadius: 50, yRadius: 50).fill()
    NSBezierPath(roundedRect: NSRect(x: 1276, y: 200, width: 180, height: 420), xRadius: 50, yRadius: 50).fill()
    let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .regular)
    if let dog = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: dog.size, flipped: false) { rect in
            dog.draw(in: rect)
            color(0x9A6110).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        // Upside down: flip it about the middle of where it lies on the cushion.
        let rect = NSRect(x: 768 - dog.size.width / 2, y: 470, width: dog.size.width, height: dog.size.height)
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: rect.midY * 2)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        tinted.draw(in: rect)
        flip.invert()
        flip.concat()
    }
}
