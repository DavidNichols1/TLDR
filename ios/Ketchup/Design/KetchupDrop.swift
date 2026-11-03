//
//  KetchupDrop.swift
//  Ketchup
//
//  The logo: a ketchup drop that is also a chat bubble. A teardrop, point
//  up, with a speech-bubble tail at the lower left.
//

import SwiftUI

/// The logo shape. Fill it with `Theme.ketchup`. It keeps its proportions,
/// centers itself in whatever frame it gets, and reads from 16 pt to 1024 pt.
/// Drawn in a unit square with cubic curves only: arcs flip direction in
/// SwiftUI's y-down space and are easy to get backwards.
nonisolated struct KetchupDrop: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x0 = rect.midX - side / 2, y0 = rect.midY - side / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x0 + x * side, y: y0 + y * side)
        }
        // The bulb is a circle centered at (0.53, 0.60) with radius 0.34.
        var path = Path()
        path.move(to: p(0.53, 0.035))
        // Right flank, tip to the widest point.
        path.addCurve(to: p(0.87, 0.60), control1: p(0.625, 0.185), control2: p(0.87, 0.37))
        // Bulb, lower right quarter.
        path.addCurve(to: p(0.53, 0.94), control1: p(0.87, 0.788), control2: p(0.718, 0.94))
        // Tail: the bottom runs on past the bulb to a point at the lower left...
        path.addCurve(to: p(0.17, 0.955), control1: p(0.40, 0.94), control2: p(0.26, 0.945))
        // ...and the back of the tail curves up into the bulb's side.
        path.addCurve(to: p(0.236, 0.77), control1: p(0.215, 0.925), control2: p(0.276, 0.839))
        // Bulb, left side up to the widest point.
        path.addCurve(to: p(0.19, 0.60), control1: p(0.206, 0.718), control2: p(0.19, 0.66))
        // Left flank back to the tip.
        path.addCurve(to: p(0.53, 0.035), control1: p(0.19, 0.37), control2: p(0.435, 0.185))
        path.closeSubpath()
        return path
    }
}

/// A highlight for big drops (the app icon, a hero): a short curved stroke
/// inside the bulb's upper left. Same unit square as `KetchupDrop`, so it
/// lines up when stacked on it. Fill it with `Theme.onKetchup`; skip it
/// below about 40 pt.
nonisolated struct DropShine: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x0 = rect.midX - side / 2, y0 = rect.midY - side / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x0 + x * side, y: y0 + y * side)
        }
        // An arc from 125 to 175 degrees, 0.24 out from the bulb's center.
        var arc = Path()
        arc.move(to: p(0.392, 0.403))
        arc.addCurve(to: p(0.291, 0.579), control1: p(0.334, 0.444), control2: p(0.297, 0.508))
        return arc.strokedPath(StrokeStyle(lineWidth: side * 0.07, lineCap: .round))
    }
}
