//
//  PhotoViewer.swift
//  Ketchup
//
//  A chat photo full screen: pinch or double-tap to zoom, drag to look
//  around, Share (which can also save it to Photos). The counter after
//  closing: the photo on dark paper, who sent it and when in cream type
//  under it. The small copy holds the place while the full one loads.
//

import SwiftUI

struct PhotoViewer: View {
    let message: Message
    /// Who sent it ("You" for your own).
    let senderName: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    /// The dark paper, in both modes.
    private static let night = Color(uiColor: UIColor(hex: 0x17120F))
    private static let cream = Color(uiColor: UIColor(hex: 0xFFF8EE))

    var body: some View {
        NavigationStack {
            ZStack {
                Self.night.ignoresSafeArea()
                if let image {
                    ZoomableImage(image: image, label: label)
                        .ignoresSafeArea()
                } else {
                    RemoteImage(object: message.smallPhoto, pixels: 1080) { small in
                        small
                            .resizable()
                            .scaledToFit()
                    } placeholder: { _ in
                        Color.clear
                    }
                    .overlay { ProgressView().tint(Self.cream) }
                    .accessibilityLabel(label)
                }
            }
            .overlay(alignment: .bottom) { caption }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview(label, image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share photo")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
        .task {
            // Full size, or the small copy if the full one can't load.
            guard let full = message.photo, let small = message.smallPhoto else { return }
            if let loaded = await RemoteImages.shared.image(full, pixels: 0) {
                image = loaded
            } else {
                image = await RemoteImages.shared.image(small, pixels: 0)
            }
        }
    }

    private var label: String {
        senderName == "You" ? "Your photo" : "Photo from \(senderName)"
    }

    /// Who sent it, when, and what they said with it, on a band of the dark paper.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(senderName)
                    .font(.subheadline.weight(.semibold))
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.mono(.caption))
                    .opacity(0.7)
            }
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.body)
                    .lineLimit(4)
            }
        }
        .foregroundStyle(Self.cream)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.night.opacity(0.8), ignoresSafeAreaEdges: .bottom)
        .accessibilityElement(children: .combine)
    }
}

/// UIKit's zooming scroll view around one image: pinch, double-tap to zoom
/// in on a spot (and back out), the system's bounce and momentum.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.show(image, label: label)
    }
}

private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var shown: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ image: UIImage, label: String) {
        imageView.accessibilityLabel = label
        guard image !== shown else { return }
        shown = image
        imageView.image = image
        zoomScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = shown, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        if zoomScale == minimumZoomScale {
            // At rest: fit the photo to the screen, and allow zooming in to
            // 3x or the photo's own pixels, whichever is more.
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
            maximumZoomScale = max(3, 1 / fit)
        }
        center()
    }

    /// Keeps a photo smaller than the screen in the middle of it.
    private func center() {
        let dx = max(0, (bounds.width - contentSize.width) / 2)
        let dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: animated)
            return
        }
        let point = tap.location(in: imageView)
        let scale = min(maximumZoomScale, 2.5)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: animated)
    }
}
