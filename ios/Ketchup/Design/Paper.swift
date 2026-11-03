//
//  Paper.swift
//  Ketchup
//
//  What things sit on: a plain card, a plan ticket with a tear line, and a
//  diner check with a torn edge. Flat paper with a hairline, no shadows.
//

import SwiftUI

extension View {
    /// Raised paper: card fill and a 1 pt rule border, no shadow. The default
    /// container for anything grouped. Fills the width.
    func paperCard(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            }
    }

    /// A plan ticket: `TicketShape` paper with a dotted tear line between the
    /// bites. Lay the content out so nothing sits on the line (the stub to
    /// the right of it suits a date or a stamp).
    func ticketCard(notchAt: CGFloat = 0.72, notchRadius: CGFloat = 9, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TicketShape(notchAt: notchAt, notchRadius: notchRadius).fill(Theme.card))
            .overlay {
                TicketShape(notchAt: notchAt, notchRadius: notchRadius)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            }
            .overlay {
                PerforationLine(notchAt: notchAt, notchRadius: notchRadius)
                    .stroke(Theme.inkFaint, style: PerforationLine.style)
            }
    }

    /// A diner check: `ReceiptShape` paper with a torn zigzag bottom, for
    /// money. Extra bottom padding keeps the content off the teeth.
    func receiptCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .padding(.bottom, ReceiptShape.toothDepth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReceiptShape().fill(Theme.card))
            .overlay { ReceiptShape().strokeBorder(Theme.rule, lineWidth: 1) }
    }
}

/// A plan ticket with its two parts placed for you: the plan left of the
/// tear line, a stub right of it (a date, a stamp). Same paper as
/// `ticketCard()`.
struct Ticket<Main: View, Stub: View>: View {
    var notchAt: CGFloat
    var main: Main
    var stub: Stub

    init(notchAt: CGFloat = 0.72, @ViewBuilder main: () -> Main, @ViewBuilder stub: () -> Stub) {
        self.notchAt = notchAt
        self.main = main()
        self.stub = stub()
    }

    var body: some View {
        TicketSplit(notchAt: notchAt) {
            main
            stub
        }
        .ticketCard(notchAt: notchAt, padding: 0)
    }
}

/// Puts a ticket's two parts either side of the tear line, inside padding.
/// The stub is centered vertically.
private struct TicketSplit: Layout {
    var notchAt: CGFloat
    var padding: CGFloat = 16
    /// Clear space either side of the tear line.
    var gap: CGFloat = 12

    private func widths(_ total: CGFloat) -> (main: CGFloat, stub: CGFloat) {
        (max(0, total * notchAt - gap - padding), max(0, total * (1 - notchAt) - gap - padding))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 340
        let w = widths(total)
        let heights = zip(subviews, [w.main, w.stub]).map { view, width in
            view.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: total, height: (heights.max() ?? 0) + padding * 2)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(bounds.width)
        if let main = subviews.first {
            main.place(at: CGPoint(x: bounds.minX + padding, y: bounds.minY + padding),
                       proposal: ProposedViewSize(width: w.main, height: bounds.height - padding * 2))
        }
        if subviews.count > 1 {
            let stub = subviews[1]
            let height = stub.sizeThatFits(ProposedViewSize(width: w.stub, height: nil)).height
            stub.place(at: CGPoint(x: bounds.minX + bounds.width * notchAt + gap,
                                   y: bounds.minY + (bounds.height - height) / 2),
                       proposal: ProposedViewSize(width: w.stub, height: height))
        }
    }
}

/// A ticket: a rounded rectangle with a half-circle bite out of the top
/// and bottom edges, both at `notchAt` (a fraction of the width, keep it
/// between 0.2 and 0.8). For plans. `ticketCard()` adds the tear line.
nonisolated struct TicketShape: InsettableShape {
    var notchAt: CGFloat = 0.72
    var notchRadius: CGFloat = 9
    var cornerRadius: CGFloat = 14
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> TicketShape {
        var shape = self
        shape.inset += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }
        let k: CGFloat = 0.5523  // a quarter circle's cubic handle, as a share of its radius
        let c = max(0, min(cornerRadius - inset, r.width / 2, r.height / 2))
        let bite = min(notchRadius + inset, r.height / 2 - 1)
        let x = rect.minX + rect.width * notchAt
        let corner = c * (1 - k)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        // Top edge, with the bite dipping into the paper.
        path.addLine(to: CGPoint(x: x - bite, y: r.minY))
        path.addCurve(to: CGPoint(x: x, y: r.minY + bite),
                      control1: CGPoint(x: x - bite, y: r.minY + k * bite),
                      control2: CGPoint(x: x - k * bite, y: r.minY + bite))
        path.addCurve(to: CGPoint(x: x + bite, y: r.minY),
                      control1: CGPoint(x: x + k * bite, y: r.minY + bite),
                      control2: CGPoint(x: x + bite, y: r.minY + k * bite))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addCurve(to: CGPoint(x: r.maxX, y: r.minY + c),
                      control1: CGPoint(x: r.maxX - corner, y: r.minY),
                      control2: CGPoint(x: r.maxX, y: r.minY + corner))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addCurve(to: CGPoint(x: r.maxX - c, y: r.maxY),
                      control1: CGPoint(x: r.maxX, y: r.maxY - corner),
                      control2: CGPoint(x: r.maxX - corner, y: r.maxY))
        // Bottom edge, right to left, with its bite.
        path.addLine(to: CGPoint(x: x + bite, y: r.maxY))
        path.addCurve(to: CGPoint(x: x, y: r.maxY - bite),
                      control1: CGPoint(x: x + bite, y: r.maxY - k * bite),
                      control2: CGPoint(x: x + k * bite, y: r.maxY - bite))
        path.addCurve(to: CGPoint(x: x - bite, y: r.maxY),
                      control1: CGPoint(x: x - k * bite, y: r.maxY - bite),
                      control2: CGPoint(x: x - bite, y: r.maxY - k * bite))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addCurve(to: CGPoint(x: r.minX, y: r.maxY - c),
                      control1: CGPoint(x: r.minX + corner, y: r.maxY),
                      control2: CGPoint(x: r.minX, y: r.maxY - corner))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addCurve(to: CGPoint(x: r.minX + c, y: r.minY),
                      control1: CGPoint(x: r.minX, y: r.minY + corner),
                      control2: CGPoint(x: r.minX + corner, y: r.minY))
        path.closeSubpath()
        return path
    }
}

/// The tear line between a ticket's two bites. Give it the same `notchAt`
/// and `notchRadius` as its `TicketShape` and the same frame, and stroke it
/// with `PerforationLine.style`.
nonisolated struct PerforationLine: Shape {
    var notchAt: CGFloat = 0.72
    var notchRadius: CGFloat = 9

    /// Round dots, 5 pt apart.
    static var style: StrokeStyle { StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]) }

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + rect.width * notchAt
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY + notchRadius + 5))
        path.addLine(to: CGPoint(x: x, y: rect.maxY - notchRadius - 5))
        return path
    }
}

/// A diner check: small rounded top corners and a zigzag bottom, as if torn
/// off the pad. For money: who owes whom, totals.
nonisolated struct ReceiptShape: InsettableShape {
    /// How deep the teeth cut, for padding content clear of them.
    static let toothDepth: CGFloat = 6

    var toothWidth: CGFloat = 12
    var cornerRadius: CGFloat = 6
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> ReceiptShape {
        var shape = self
        shape.inset += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let depth = Self.toothDepth
        guard r.width > 0, r.height > depth else { return Path() }
        let k: CGFloat = 0.5523
        let c = max(0, min(cornerRadius - inset, r.width / 2, (r.height - depth) / 2))
        let corner = c * (1 - k)
        let teeth = max(1, Int((r.width / toothWidth).rounded()))
        let tooth = r.width / CGFloat(teeth)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addCurve(to: CGPoint(x: r.maxX, y: r.minY + c),
                      control1: CGPoint(x: r.maxX - corner, y: r.minY),
                      control2: CGPoint(x: r.maxX, y: r.minY + corner))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        // The torn edge, right to left: down to each tooth's point, back up.
        for i in 0..<teeth {
            let right = r.maxX - CGFloat(i) * tooth
            path.addLine(to: CGPoint(x: right - tooth / 2, y: r.maxY))
            path.addLine(to: CGPoint(x: right - tooth, y: r.maxY - depth))
        }
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addCurve(to: CGPoint(x: r.minX + c, y: r.minY),
                      control1: CGPoint(x: r.minX, y: r.minY + corner),
                      control2: CGPoint(x: r.minX + corner, y: r.minY))
        path.closeSubpath()
        return path
    }
}
