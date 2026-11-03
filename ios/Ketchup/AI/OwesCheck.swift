//
//  OwesCheck.swift
//  Ketchup
//
//  "Who owes what" as a diner check: the reader's lines first with their
//  total marked, everyone else's after, and the things to bring at the
//  bottom. Muse Spark writes each amount into a phrase ("$90 for Airbnb");
//  the amount and the item are read back out of it here.
//

import SwiftUI

/// The owes, sorted the way a check reads. The reader is "You".
struct Tab {
    struct Line {
        let from: String
        let to: String?
        /// "Airbnb", "Speaker and Catan".
        let label: String
        let amount: Decimal?
        let symbol: String
        let refs: [UUID]
    }

    /// What the reader owes, then what's owed to them.
    private(set) var yours: [Line] = []
    /// Money between other people.
    private(set) var others: [Line] = []
    /// No amount: things to bring or do.
    private(set) var toBring: [Line] = []
    private(set) var youOwe: Decimal = 0
    private(set) var owedToYou: Decimal = 0
    /// The currency each total is in, from the lines that make it up.
    private(set) var youOweSymbol = "$"
    private(set) var owedSymbol = "$"

    init(_ owes: [CatchUp.Owe], reader: String) {
        var owing: [Line] = [], owed: [Line] = [], mineToBring: [Line] = []
        for owe in owes {
            let fromReader = Self.isReader(owe.who, reader: reader)
            let toReader = Self.isReader(owe.owesWhom, reader: reader)
            let (amount, symbol, label) = Self.parse(owe.what)
            let line = Line(from: fromReader ? "You" : owe.who,
                            to: owe.owesWhom.map { toReader ? "You" : $0 },
                            label: label, amount: amount, symbol: symbol, refs: owe.refs)
            guard let amount else {
                if fromReader { mineToBring.append(line) } else { toBring.append(line) }
                continue
            }
            if fromReader {
                owing.append(line)
                youOwe += amount
                youOweSymbol = symbol
            } else if toReader {
                owed.append(line)
                owedToYou += amount
                owedSymbol = symbol
            } else {
                others.append(line)
            }
        }
        yours = owing + owed
        toBring = mineToBring + toBring
    }

    /// The model names the reader the way the chat does ("David"), and now
    /// and then "you".
    static func isReader(_ name: String?, reader: String) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else { return false }
        if name == "you" || name == "me" { return true }
        let reader = reader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !reader.isEmpty else { return false }
        return name == reader || name == reader.split(separator: " ").first.map(String.init)
    }

    /// "$90 for Airbnb" gives (90, "$", "Airbnb"); "Bring the speaker and
    /// Catan" gives no amount and "Speaker and Catan".
    static func parse(_ what: String) -> (amount: Decimal?, symbol: String, label: String) {
        let string = what as NSString
        guard let match = money.firstMatch(in: what, range: NSRange(location: 0, length: string.length)) else {
            return (nil, "$", label(what, dropping: ["bring ", "brings "], afterFor: false))
        }
        let digits = string.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")
        let amount = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
        return (amount, string.substring(with: match.range(at: 1)),
                label(string.replacingCharacters(in: match.range, with: " "), dropping: [], afterFor: true))
    }

    /// "$90.00", in the reader's number format.
    static func format(_ amount: Decimal, symbol: String) -> String {
        symbol + amount.formatted(.number.precision(.fractionLength(2)))
    }

    /// An amount: "$90", "$1,200.50", "€45" (and not the comma in "$540, so").
    private static let money = try! NSRegularExpression(pattern: #"([$€£])\s?(\d+(?:,\d{3})*(?:\.\d{1,2})?)"#)

    /// What's left of the phrase once the amount is out, as an item: what
    /// follows "for" when money has one ("Send Maya $90 for the Airbnb"),
    /// no "the", a capital letter.
    private static func label(_ raw: String, dropping verbs: [String], afterFor: Bool) -> String {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if afterFor, let range = text.range(of: " for ", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in verbs + ["for ", "the "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// A line as a sentence for VoiceOver: "You owe Maya $90.00 for Airbnb",
    /// "Maya owes you $20.00 for Gas", "You: Speaker and Catan".
    static func spoken(_ line: Line) -> String {
        guard let amount = line.amount else { return "\(line.from): \(line.label)" }
        let verb = line.from == "You" ? "owe" : "owes"
        let whom = line.to.map { $0 == "You" ? " you" : " \($0)" } ?? ""
        let item = line.label.isEmpty ? "" : " for \(line.label)"
        return "\(line.from) \(verb)\(whom) \(format(amount, symbol: line.symbol))\(item)"
    }
}

struct OwesCheck: View {
    let owes: [CatchUp.Owe]
    let readerName: String
    let refs: RefContext

    /// The total gets marked once it has scrolled into view.
    @State private var totalSeen = false

    var body: some View {
        let tab = Tab(owes, reader: readerName)
        VStack(alignment: .leading, spacing: 0) {
            if !tab.yours.isEmpty {
                Kicker("Your tab")
                    .padding(.bottom, 8)
                lines(tab.yours)
                DashedRule()
                    .padding(.vertical, 12)
                totals(tab)
            }
            if !tab.others.isEmpty {
                Kicker(tab.yours.isEmpty ? "The table" : "Everyone else")
                    .padding(.top, tab.yours.isEmpty ? 0 : 26)
                    .padding(.bottom, 8)
                lines(tab.others)
            }
            if !tab.toBring.isEmpty {
                Kicker("To bring")
                    .padding(.top, tab.yours.isEmpty && tab.others.isEmpty ? 0 : 26)
                    .padding(.bottom, 8)
                lines(tab.toBring)
            }
            Text("Tap a line to see where it was said.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
        }
        .receiptCard(padding: 18)
    }

    private func lines(_ lines: [Tab.Line]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    /// "You → Maya  Airbnb ........ $90.00"; tapping it jumps to the message.
    private func row(_ line: Tab.Line) -> some View {
        Button {
            if let first = line.refs.first { refs.jump(first) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title(line)
                    .font(.mono(.subheadline))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let amount = line.amount {
                    Text(Tab.format(amount, symbol: line.symbol))
                        .font(.mono(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                }
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .disabled(line.refs.isEmpty)
        .accessibilityLabel(Tab.spoken(line))
        .accessibilityHint(refs.hint)
    }

    private func title(_ line: Tab.Line) -> Text {
        let item = Text(verbatim: line.label).foregroundStyle(Theme.inkSoft)
        guard let to = line.to else {
            return Text("\(name(line.from))  \(item)")
        }
        return Text("\(name(line.from))\(Text(verbatim: " → ").foregroundStyle(Theme.inkSoft))\(name(to))  \(item)")
    }

    private func name(_ name: String) -> Text {
        Text(verbatim: name)
            .fontWeight(.semibold)
            .foregroundStyle(RefChip.color(for: name))
    }

    @ViewBuilder
    private func totals(_ tab: Tab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if tab.youOwe > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("You owe")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 12)
                    Text(Tab.format(tab.youOwe, symbol: tab.youOweSymbol))
                        .font(.mono(.title3, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .marked(totalSeen, sweep: true)
                        .onScrollVisibilityChange(threshold: 0.9) { visible in
                            if visible { totalSeen = true }
                        }
                }
                .accessibilityElement(children: .combine)
            }
            if tab.owedToYou > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Owed to you")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 12)
                    Text(Tab.format(tab.owedToYou, symbol: tab.owedSymbol))
                        .font(.mono(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The dashed line above a check's total.
private struct DashedRule: View {
    var body: some View {
        DashedLine()
            .stroke(Theme.inkSoft, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

nonisolated private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
