//
//  PreviewPhotos.swift
//  Ketchup
//
//  Made-up photos for offline previews, drawn on the fly: a symbol on a
//  person's color for profile photos, a mountain scene for the cropper, and
//  a cabin, the mountains and a dog for chat photos. Never real people. In
//  preview mode RemoteImages asks here instead of the network.
//

#if DEBUG
import UIKit

nonisolated enum PreviewPhotos {

    /// The avatars-bucket path of a demo person's made-up photo, or nil for
    /// the people who keep their monogram (Sam, and anyone not listed).
    static func avatarPath(for name: String) -> String? {
        art(for: name) == nil ? nil : "preview/\(name.lowercased()).jpg"
    }

    /// The bytes for a preview path; nil for anything else.
    static func data(for object: StorageObject) -> Data? {
        guard object.path.hasPrefix("preview/") else { return nil }
        var name = object.path.dropFirst("preview/".count).replacingOccurrences(of: ".jpg", with: "")
        if object.bucket == Storage.chatMedia {
            let small = name.hasSuffix("_small")
            if small { name = String(name.dropLast("_small".count)) }
            guard let scene = scene(name) else { return nil }
            return (small ? resized(scene, longSide: 768) : scene).jpegData(compressionQuality: 0.8)
        }
        guard let art = art(for: name) else { return nil }
        return portrait(symbol: art.symbol, background: art.background).jpegData(compressionQuality: 0.85)
    }

    /// A chat photo's path in previews ("preview/cabin.jpg") and its size.
    static func chatPhoto(_ name: String) -> (path: String, width: Int, height: Int)? {
        guard let image = scene(name) else { return nil }
        return ("preview/\(name).jpg", Int(image.size.width), Int(image.size.height))
    }

    /// A made-up photo ready to send, as if just picked.
    static func prepared(_ name: String) -> PreparedPhoto? {
        scene(name)?.jpegData(compressionQuality: 0.9).flatMap(PhotoPrep.prepared)
    }

    /// The made-up chat photos: "cabin", "mountains", "pickles" (the dog) and
    /// "door" (the door code on a sticky note, as in the demo seed's photo).
    private static func scene(_ name: String) -> UIImage? {
        switch name {
        case "cabin": cabin()
        case "mountains": landscape()
        case "pickles": dog()
        case "door": doorNote()
        default: nil
        }
    }

    /// A sticky note on the cabin door, next to the keypad, 1536 x 1152.
    private static func doorNote() -> UIImage {
        let size = CGSize(width: 1536, height: 1152)
        return render(size) { ctx in
            let cg = ctx.cgContext
            UIColor(hex: 0x74452A).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0x613A22).setFill()
            for x in stride(from: 0.0, to: 1536, by: 192) { cg.fill(CGRect(x: x, y: 0, width: 12, height: 1152)) }
            UIColor(hex: 0x2E2E33).setFill()
            UIBezierPath(roundedRect: CGRect(x: 1080, y: 392, width: 300, height: 460), cornerRadius: 28).fill()
            UIColor(hex: 0xD9D9D1).setFill()
            for row in 0..<4 {
                for col in 0..<3 {
                    cg.fillEllipse(in: CGRect(x: 1120 + col * 84, y: 442 + row * 96, width: 60, height: 60))
                }
            }
            UIColor(hex: 0xF3B33D).setFill()
            let note = CGRect(x: 220, y: 292, width: 640, height: 520)
            cg.fill(note)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            func write(_ text: String, y: CGFloat, size: CGFloat, weight: UIFont.Weight) {
                text.draw(in: CGRect(x: note.minX, y: y, width: note.width, height: size * 1.3),
                          withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight),
                                           .foregroundColor: UIColor(hex: 0x2A1E19), .paragraphStyle: style])
            }
            write("cabin door code", y: 340, size: 60, weight: .medium)
            write("4471", y: 420, size: 176, weight: .bold)
            write("hit # after", y: 690, size: 52, weight: .regular)
        }
    }

    /// The photo the cropper preview frames: a made-up mountain day.
    static func landscape() -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        return render(size) { ctx in
            UIColor(hex: 0xC9DDE8).setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xF3B33D).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 1120, y: 170, width: 210, height: 210))
            mountain(peak: CGPoint(x: 560, y: 330), base: 980, width: 1180, color: 0x4F5B66)
            mountain(peak: CGPoint(x: 1130, y: 470), base: 980, width: 1000, color: 0x1E6E6A)
            UIColor(hex: 0xE4ECEF).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 960, width: size.width, height: 240))
            UIColor(hex: 0x3C6B2F).setFill()
            for x in stride(from: 90.0, to: 1600, by: 210) {
                tree(at: CGPoint(x: x, y: 1010))
            }
        }
    }

    /// A snowy cabin at dusk with its windows lit, 1200 x 1500.
    private static func cabin() -> UIImage {
        let size = CGSize(width: 1200, height: 1500)
        return render(size) { ctx in
            let cg = ctx.cgContext
            UIColor(hex: 0x2C4A86).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xFFF8EE, alpha: 0.85).setFill()
            for (x, y) in [(140, 160), (420, 90), (760, 210), (1010, 120), (300, 330), (930, 380)] {
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 9, height: 9))
            }
            mountain(peak: CGPoint(x: 330, y: 520), base: 1060, width: 1100, color: 0x4F5B66)
            mountain(peak: CGPoint(x: 940, y: 600), base: 1060, width: 900, color: 0x3A302A)
            UIColor(hex: 0xE4ECEF).setFill()
            cg.fill(CGRect(x: 0, y: 1040, width: size.width, height: 460))
            // The cabin: walls, a door, two lit windows, a roof with snow on it.
            UIColor(hex: 0x74452A).setFill()
            cg.fill(CGRect(x: 330, y: 860, width: 540, height: 360))
            UIColor(hex: 0x3A2418).setFill()
            cg.fill(CGRect(x: 560, y: 1020, width: 110, height: 200))
            UIColor(hex: 0xF3B33D).setFill()
            cg.fill(CGRect(x: 395, y: 930, width: 110, height: 100))
            cg.fill(CGRect(x: 705, y: 930, width: 110, height: 100))
            let roof = UIBezierPath()
            roof.move(to: CGPoint(x: 290, y: 880))
            roof.addLine(to: CGPoint(x: 600, y: 640))
            roof.addLine(to: CGPoint(x: 910, y: 880))
            roof.close()
            UIColor(hex: 0xFFFDF8).setFill()
            roof.fill()
            UIColor(hex: 0x3C6B2F).setFill()
            for x in stride(from: 70.0, to: 1200, by: 260) where !(250...950).contains(x) {
                tree(at: CGPoint(x: x, y: 1120))
            }
        }
    }

    /// A dog on the snow, 1500 x 1125.
    private static func dog() -> UIImage {
        let size = CGSize(width: 1500, height: 1125)
        return render(size) { ctx in
            let cg = ctx.cgContext
            UIColor(hex: 0xC9DDE8).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xE4ECEF).setFill()
            cg.fill(CGRect(x: 0, y: 760, width: size.width, height: 365))
            let config = UIImage.SymbolConfiguration(pointSize: 560, weight: .regular)
            if let glyph = UIImage(systemName: "dog.fill", withConfiguration: config)?
                .withTintColor(UIColor(hex: 0x9A6110), renderingMode: .alwaysOriginal) {
                glyph.draw(in: CGRect(x: (size.width - glyph.size.width) / 2, y: 900 - glyph.size.height,
                                      width: glyph.size.width, height: glyph.size.height))
            }
        }
    }

    private static func resized(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let scale = longSide / max(image.size.width, image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return render(size) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: Drawing

    private static func art(for name: String) -> (symbol: String, background: UInt32)? {
        switch name.lowercased() {
        case "david": ("mountain.2.fill", 0x9A6110)
        case "maya": ("figure.skiing.downhill", 0x1E6E6A)
        case "jordan": ("car.side.fill", 0xB4472E)
        case "priya": ("books.vertical.fill", 0x7A3E73)
        case "theo": ("dog.fill", 0x2C4A86)
        default: nil
        }
    }

    /// A square "photo": a symbol standing on a lighter floor.
    private static func portrait(symbol: String, background: UInt32) -> UIImage {
        let side: CGFloat = 512
        return render(CGSize(width: side, height: side)) { ctx in
            // cgContext.fill blends; the renderer context's own fill copies.
            UIColor(hex: background).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor(hex: 0xFFF8EE, alpha: 0.18).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: side * 0.68, width: side, height: side * 0.32))
            let config = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .regular)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(UIColor(hex: 0xFFF8EE), renderingMode: .alwaysOriginal) {
                let rect = CGRect(x: (side - glyph.size.width) / 2, y: side * 0.70 - glyph.size.height,
                                  width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: rect)
            }
        }
    }

    private static func mountain(peak: CGPoint, base: CGFloat, width: CGFloat, color: UInt32) {
        let body = UIBezierPath()
        body.move(to: CGPoint(x: peak.x - width / 2, y: base))
        body.addLine(to: peak)
        body.addLine(to: CGPoint(x: peak.x + width / 2, y: base))
        body.close()
        UIColor(hex: color).setFill()
        body.fill()
        // Snow on the top fifth.
        let drop = (base - peak.y) * 0.2
        let spread = width / 2 * 0.2
        let cap = UIBezierPath()
        cap.move(to: peak)
        cap.addLine(to: CGPoint(x: peak.x + spread, y: peak.y + drop))
        cap.addLine(to: CGPoint(x: peak.x + spread * 0.3, y: peak.y + drop * 0.8))
        cap.addLine(to: CGPoint(x: peak.x - spread * 0.4, y: peak.y + drop))
        cap.addLine(to: CGPoint(x: peak.x - spread, y: peak.y + drop))
        cap.close()
        UIColor(hex: 0xFFFDF8).setFill()
        cap.fill()
    }

    private static func tree(at foot: CGPoint) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: foot.x - 45, y: foot.y))
        path.addLine(to: CGPoint(x: foot.x, y: foot.y - 170))
        path.addLine(to: CGPoint(x: foot.x + 45, y: foot.y))
        path.close()
        path.fill()
    }

    private static func render(_ size: CGSize, _ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: draw)
    }
}
#endif
