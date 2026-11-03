//
//  ForYouList.swift
//  Ketchup
//
//  "For you": the reader's to-dos as a checklist on one card. Tapping the
//  circle checks one off (a pickle check, a pen stroke through it); that
//  lives only in this sheet. Tapping the words jumps to where it was said.
//

import SwiftUI

struct ForYouList: View {
    let items: [CatchUp.Item]
    let refs: RefContext

    @State private var done: Set<Int> = []
    #if DEBUG
    @Environment(\.previewDone) private var previewDone
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 {
                    Theme.rule
                        .frame(height: 1)
                        .padding(.leading, 54)
                }
                ToDoRow(item: item, isDone: done.contains(i), refs: refs) {
                    if done.contains(i) { done.remove(i) } else { done.insert(i) }
                }
            }
        }
        .paperCard(padding: 0)
        #if DEBUG
        .onAppear { if !previewDone.isEmpty { done = previewDone } }
        #endif
    }
}

private struct ToDoRow: View {
    let item: CatchUp.Item
    let isDone: Bool
    let refs: RefContext
    let toggle: () -> Void

    @ScaledMetric(relativeTo: .body) private var box: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                check
            }
            .buttonStyle(.pressable)
            // Lays out at the ring's size; the extra 10 pt all round is
            // still there to tap.
            .padding(-10)
            .sensoryFeedback(.selection, trigger: isDone)
            .accessibilityLabel(item.text)
            .accessibilityValue(isDone ? "Done" : "Not done")
            .accessibilityAddTraits(.isToggle)

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if let first = item.refs.first { refs.jump(first) }
                } label: {
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(isDone ? Theme.inkSoft : Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .struck(isDone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .disabled(item.refs.isEmpty)
                // The check above already read the words out.
                .accessibilityLabel("Show where it was said")

                RefChips(refs: item.refs, context: refs)
                    .opacity(isDone ? 0.55 : 1)
                    .motion(value: isDone)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// An empty ring, or a pickle dot with a check that pops in.
    private var check: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? Theme.pickle : Theme.inkSoft, lineWidth: 1.5)
            Circle()
                .fill(Theme.pickle)
                .scaleEffect(isDone ? 1 : 0.3)
                .opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: box * 0.48, weight: .bold))
                .foregroundStyle(Theme.card)
                .scaleEffect(isDone ? 1 : 0.4)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: box, height: box)
        // A 44 pt target around a 24 pt ring.
        .padding(10)
        .motion(Motion.lively, value: isDone)
    }
}

#if DEBUG
extension EnvironmentValues {
    /// Preview only: the to-dos that start checked off (`-screen ai-checked`).
    @Entry var previewDone: Set<Int> = []
}
#endif
