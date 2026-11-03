//
//  BriefText.swift
//  Ketchup
//
//  Muse Spark's sentences, marked up for skimming: money and times get the
//  mustard marker on their own, the reader's name stands out in a question,
//  a first sentence can stand as a headline, and a to-do gets a pen stroke
//  through it once it's done.
//

import SwiftUI

/// Builds a `Text` with the parts of a sentence worth marking tagged by
/// `markedRun()`. Show it with `.markRuns()`.
enum BriefMarks {

    /// Money and times: "$90", "$1,200.50", "Saturday 6am", "Thursday noon",
    /// "7:30", "5:45am", and a bare day after "by", "before" or "until"
    /// ("confirm by Thursday"). Other day names stay plain ("the Friday
    /// storm"), and so does an old amount ("down from $140", "instead of
    /// $140", "was $140").
    static func moneyAndTimes(_ text: String) -> Text {
        marked(text, by: moneyAndTimesPattern)
    }

    /// Every mention of `name` as a name: the reader, in someone's question.
    static func name(_ name: String, in text: String) -> Text {
        guard let pattern = namePattern(name) else { return Text(verbatim: text) }
        return marked(text, by: pattern)
    }

    /// Whether `text` mentions `name` as a name.
    static func mentions(_ name: String, in text: String) -> Bool {
        guard let pattern = namePattern(name) else { return false }
        return pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// The whole word, capitalized the way Muse Spark writes names, so a
    /// reader called Will doesn't light up every "will".
    private static func namePattern(_ name: String) -> NSRegularExpression? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        return try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: capitalized))\\b")
    }

    private static let moneyAndTimesPattern: NSRegularExpression = {
        let day = "(?:mon|tues|wednes|thurs|fri|satur|sun)day"
        let clock = #"\d{1,2}(?::\d{2})?\s?(?:am|pm|a\.m\.|p\.m\.)(?![a-z])|\d{1,2}:\d{2}"#
        let time = "(?:\(clock)|noon|midnight)"
        let pattern = [
            #"(?<!\bfrom )(?<!\binstead of )(?<!\bwas )[$€£]\d+(?:,\d{3})*(?:\.\d{1,2})?"#,
            "\\b\(day)\\s+(?:at\\s+)?\(time)",
            "(?<=\\b(?:by|before|until) )\(day)",
            "\\b\(time)",
        ].joined(separator: "|")
        // A fixed pattern: if it didn't compile, that's a typo to fix here.
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    private static func marked(_ text: String, by pattern: NSRegularExpression) -> Text {
        let string = text as NSString
        var result = Text(verbatim: "")
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let range = match.range
            if range.location > cursor {
                let plain = string.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result = Text("\(result)\(Text(verbatim: plain))")
            }
            result = Text("\(result)\(Text(verbatim: string.substring(with: range)).markedRun())")
            cursor = range.location + range.length
        }
        if cursor < string.length {
            result = Text("\(result)\(Text(verbatim: string.substring(from: cursor)))")
        }
        return result
    }
}

// MARK: - Sentences

enum Sentences {
    /// "Muse Spark is busy right now. Try again in a moment." gives the first
    /// sentence, to set as a headline, and the rest, to go under it.
    static func first(_ text: String) -> (first: String, rest: String?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stop = text.range(of: #"[.?!]\s+"#, options: .regularExpression) else { return (text, nil) }
        let first = text[..<stop.upperBound].trimmingCharacters(in: .whitespaces)
        let rest = text[stop.upperBound...].trimmingCharacters(in: .whitespaces)
        return (first, rest.isEmpty ? nil : rest)
    }
}

// MARK: - Struck through

extension View {
    /// A pen stroke through the text, drawn left to right across each line in
    /// turn: a to-do that's done. Quick and plain with Reduce Motion on.
    func struck(_ isOn: Bool, color: Color = Theme.inkSoft) -> some View {
        modifier(StrikeModifier(isOn: isOn, color: color))
    }
}

private struct StrikeModifier: ViewModifier {
    let isOn: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .textRenderer(StrikeRenderer(progress: isOn ? 1 : 0, color: color))
            .animation(reduceMotion ? Motion.fade : (isOn ? Motion.sweep : Motion.snappy), value: isOn)
    }
}

/// Draws each line, then the stroke over it. `progress` runs across all the
/// lines as if they were one, so a three-line to-do gets struck in order.
nonisolated private struct StrikeRenderer: TextRenderer {
    var progress: CGFloat
    var color: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let total = layout.reduce(0) { $0 + $1.typographicBounds.width }
        var left = total * min(max(progress, 0), 1)
        for line in layout {
            context.draw(line)
            let bounds = line.typographicBounds
            let length = min(bounds.width, left)
            left -= bounds.width
            guard length > 0.5 else { continue }
            // Through the middle of the lowercase letters.
            let y = bounds.origin.y - bounds.ascent * 0.32
            var stroke = Path()
            stroke.move(to: CGPoint(x: bounds.origin.x - 1, y: y))
            stroke.addLine(to: CGPoint(x: bounds.origin.x + length + 1, y: y))
            context.stroke(stroke, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}
