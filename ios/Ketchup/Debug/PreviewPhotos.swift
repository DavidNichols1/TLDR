//
//  PreviewPhotos.swift
//  Ketchup
//
//  Made-up photos for offline previews, drawn on the fly: a symbol on a
//  person's color for profile photos, a mountain scene for the cropper.
//  Never real people. In preview mode RemoteImages asks here instead of the
//  network.
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
        guard object.bucket == Storage.avatars, object.path.hasPrefix("preview/") else { return nil }
        let name = object.path.dropFirst("preview/".count).replacingOccurrences(of: ".jpg", with: "")
        guard let art = art(for: name) else { return nil }
        return portrait(symbol: art.symbol, background: art.background).jpegData(compressionQuality: 0.85)
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
