//
//  SparkleLoading.swift
//  TLDR
//
//  While Muse Spark reads: a breathing sparkle and shimmering placeholder
//  lines shaped like the answer that's coming.
//

import SwiftUI

struct SparkleLoading: View {
    let title: String
    var lines: [CGFloat] = [1, 0.92, 0.7, 0, 0.85, 0.6, 0, 0.95, 0.75]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: Theme.aiSymbol)
                    .font(.title2)
                    .foregroundStyle(Theme.aiGradient)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    .symbolEffect(.breathe, options: .repeating)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.aiGradient)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, width in
                    if width == 0 {
                        Color.clear.frame(height: 6)
                    } else {
                        ShimmerBar()
                            .containerRelativeFrame(.horizontal) { length, _ in length * width * 0.82 }
                    }
                }
            }
        }
        .aiCard(padding: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)…")
    }
}

/// A rounded bar with a light sweep moving across it.
struct ShimmerBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.violet.opacity(0.13))
            .frame(height: 12)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
