//
//  ThreadDivider.swift
//  Ketchup
//
//  The centered lines between bubbles: a day ("Yesterday") or the start of
//  what's new ("312 new messages").
//

import SwiftUI

struct ThreadDivider: View {
    let text: String
    var isUnread = false

    var body: some View {
        HStack(spacing: 10) {
            if isUnread { line }
            Text(text)
                .font(.caption.weight(isUnread ? .bold : .semibold))
                .foregroundStyle(isUnread ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(.secondary))
                .padding(.horizontal, isUnread ? 0 : 10)
                .padding(.vertical, isUnread ? 0 : 4)
                .background(isUnread ? Color.clear : Color.primary.opacity(0.05), in: Capsule())
            if isUnread { line }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.aiGradient.opacity(0.5))
            .frame(height: 1)
    }
}
