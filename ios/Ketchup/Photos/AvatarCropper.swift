//
//  AvatarCropper.swift
//  Ketchup
//
//  Framing a new profile photo. The photo sits under a window cut in the
//  paper, the same rounded square every avatar is drawn in; drag and pinch
//  to frame it. "Use photo" draws exactly what's in the window as a 512 px
//  JPEG and saves it, and the sheet stays up, saying so, until that's done.
//  Adapted from AurariaGO's AvatarCropperView.
//

import SwiftUI

struct AvatarCropper: View {
    /// Upright, already capped in size (`PhotoPrep.upright`).
    let image: UIImage
    /// Uploads and saves the photo; throws to show why it couldn't.
    let save: (Data) async throws -> Void

    /// The square that's saved, in pixels.
    static let outputPixels: CGFloat = 512

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// The space the photo has between the title and the buttons.
    @State private var area: CGSize = .zero
    @State private var saving = false
    @State private var error: String?

    /// The window's side, in points.
    private var side: CGFloat { max(1, min(area.width - 48, area.height - 16)) }
    /// Points per pixel at zoom 1: the photo's short side spans the window.
    private var base: CGFloat { side / max(1, min(image.size.width, image.size.height)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Color.clear
                .overlay { frame }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
            footer
        }
        .background(Theme.cream)
        .interactiveDismissDisabled(saving)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Kicker("Profile photo")
            Text("Frame it")
                .font(.serif(.title2))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Drag and pinch to fit the square.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    /// The photo under paper with the window cut out of it.
    private var frame: some View {
        let window = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                .offset(offset)
            Theme.cream.opacity(0.86)
                .overlay {
                    window
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            window
                .strokeBorder(Theme.ink, lineWidth: 1)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
        // A fixed frame, so the oversized photo can't stretch the layout.
        .frame(width: area.width, height: area.height)
        .clipped()
        .contentShape(.rect)
        .gesture(drag.simultaneously(with: pinch))
        .accessibilityElement()
        .accessibilityLabel("Your photo, framed")
        .accessibilityValue("Zoom \(Int((zoom * 100).rounded())) percent")
        .accessibilityHint("Drag and pinch to fit the square, or swipe up or down to zoom.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: zoom = min(zoom + 0.25, 6)
            case .decrement: zoom = max(zoom - 0.25, 1)
            @unknown default: break
            }
            lastZoom = zoom
            settle()
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error {
                FormError(text: error)
            }
            Button {
                Task { await use() }
            } label: {
                if saving {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.onKetchup)
                        Text("Saving")
                    }
                } else {
                    Text("Use photo")
                }
            }
            .buttonStyle(.ketchup)
            Button("Cancel") { dismiss() }
                .buttonStyle(.outline)
        }
        .disabled(saving)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: Gestures

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in settle() }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(lastZoom * value.magnification, 1), 6) }
            .onEnded { _ in
                lastZoom = zoom
                settle()
            }
    }

    /// Slides the photo back until it covers the window again.
    private func settle() {
        let fixed = clamped(offset)
        withAnimation(Motion.choose(Motion.snappy, reduceMotion: reduceMotion)) { offset = fixed }
        lastOffset = fixed
    }

    private func clamped(_ o: CGSize) -> CGSize {
        let maxX = max(0, (image.size.width * base * zoom - side) / 2)
        let maxY = max(0, (image.size.height * base * zoom - side) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    // MARK: Output

    private func use() async {
        guard let jpeg = rendered() else {
            error = "Couldn't read that photo. Try another one."
            return
        }
        saving = true
        error = nil
        do {
            try await save(jpeg)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }

    /// What's inside the window, drawn into a 512 px square JPEG.
    private func rendered() -> Data? {
        let out = Self.outputPixels
        let k = out / side
        let o = clamped(offset)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            let s = base * zoom * k
            let size = CGSize(width: image.size.width * s, height: image.size.height * s)
            let origin = CGPoint(x: out / 2 + o.width * k - size.width / 2,
                                 y: out / 2 + o.height * k - size.height / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
        return square.jpegData(compressionQuality: 0.82)
    }
}
