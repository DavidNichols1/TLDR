//
//  DesignGallery.swift
//  Ketchup
//
//  `-screen design`: every piece of Theme and Design/ on one page, in light
//  or dark. `-section brand|buttons|marker|type|people|paper|colors` scrolls
//  to a part, for screenshots.
//

#if DEBUG
import SwiftUI

struct DesignGallery: View {
    static let name = "design"

    @State private var sweepOn = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    brand.id("brand")
                    buttons.id("buttons")
                    marker.id("marker")
                    type.id("type")
                    people.id("people")
                    paper.id("paper")
                    colors.id("colors")
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Theme.cream)
            .task {
                guard let section = PreviewData.section else { return }
                try? await Task.sleep(for: .milliseconds(150))
                proxy.scrollTo(section, anchor: .top)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Ketchup design system")
            Text("The counter")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
            Text("Cream paper, warm ink, ketchup for the one thing to press, mustard for what matters, pickle for confirmed.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var brand: some View {
        section("Brand", kicker: "Wordmark, KetchupDrop") {
            Wordmark(size: 56, drawIn: true)
            HStack(alignment: .bottom, spacing: 16) {
                ForEach([16, 24, 32, 48, 72] as [CGFloat], id: \.self) { size in
                    VStack(spacing: 6) {
                        KetchupDrop()
                            .fill(Theme.ketchup)
                            .frame(width: size, height: size)
                        Text("\(Int(size))")
                            .font(.mono(.caption2))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            }
            HStack(spacing: 16) {
                iconIdea(paper: 0xFBF5EA, drop: 0xD7372B, shine: 0xFFF8EE)
                iconIdea(paper: 0xD7372B, drop: 0xFBF5EA, shine: 0xD7372B)
                iconIdea(paper: 0x2A1E19, drop: 0xE8473A, shine: 0xFFF8EE)
            }
            caption("Icon ideas, with DropShine. The drop reads down to 16 pt.")
        }
    }

    private var buttons: some View {
        section("Buttons", kicker: ".ketchup  .ink  .outline  .pressable") {
            styleRow("ketchup: the one thing to press") {
                Button("Catch me up") {}.buttonStyle(.ketchup)
                Button("Catch me up") {}.buttonStyle(.ketchup).disabled(true)
            }
            styleRow("ink: a strong second choice") {
                Button("Ask the chat") {}.buttonStyle(.ink)
                Button("Ask the chat") {}.buttonStyle(.ink).disabled(true)
            }
            styleRow("outline: a quiet one") {
                Button("Join a chat") {}.buttonStyle(.outline)
                Button("Join a chat") {}.buttonStyle(.outline).disabled(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("compact, for inside cards")
                HStack(spacing: 10) {
                    Button("Add to calendar") {}.buttonStyle(.ketchup(.compact))
                    Button("Try again") {}.buttonStyle(.ink(.compact))
                    Button("Copy") {}.buttonStyle(.outline(.compact))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("pressable, for cards and rows")
                Button {} label: {
                    HStack(spacing: 12) {
                        Monogram(name: "Breck Weekend", color: Theme.ketchup, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Breck Weekend 🎿").font(.headline).foregroundStyle(Theme.ink)
                            Text("Maya: goodnight losers 💙").font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text("302")
                            .font(.mono(.caption, weight: .bold))
                            .foregroundStyle(Theme.onMustard)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.mustard, in: Capsule())
                    }
                    .paperCard(padding: 12)
                }
                .buttonStyle(.pressable)
            }
            caption("Right: disabled, at 40%. Press .ketchup for its light haptic.")
        }
    }

    private var marker: some View {
        section("Marker", kicker: "marked(), MarkerStroke") {
            HStack(spacing: 0) {
                Text("You owe Maya ")
                Text("$90").marked()
                Text(" for the Airbnb.")
            }
            .font(.body)
            .foregroundStyle(Theme.ink)
            Text("Saturday, 6:00 AM")
                .font(.mono(.headline))
                .foregroundStyle(Theme.ink)
                .marked(sweepOn, sweep: true)
            Text("Hearthstone moved to 7:30")
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
                .marked(sweepOn, sweep: true, delay: Motion.stagger * 4)
            if sweepOn {
                sentence.markRuns(sweep: true, delay: Motion.stagger * 8)
            } else {
                sentence
            }
            Button("Sweep again") {
                sweepOn = false
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    sweepOn = true
                }
            }
            .buttonStyle(.outline(.compact))
            caption("marked() for a phrase on one line; markedRun() + markRuns() inside a sentence that wraps. Sweeps with Motion.sweep; just appears with Reduce Motion.")
        }
    }

    private var sentence: some View {
        Text("Leave \(Text("Saturday at 6:00").markedRun()) from Maya's, and send her \(Text("$90").markedRun()) for the Airbnb before the trip.")
            .font(.body)
            .foregroundStyle(Theme.ink)
    }

    private var type: some View {
        section("Type", kicker: "New York, SF Pro, SF Mono") {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("For you")
                SectionTitle("Plans", count: 6)
                Text("Large title in New York").font(.serif(.largeTitle))
                Text("Title in New York").font(.serif(.title))
                Text("Title 3 in New York").font(.serif(.title3))
                Text("Body is SF Pro: plain words for plain reading.").font(.body)
                Text("Footnote, SF Pro, inkSoft").font(.footnote).foregroundStyle(Theme.inkSoft)
                Text("6:00 AM  $90.00  WQGAEA  302").font(.mono(.body))
                Kicker("Read by \(Theme.modelName)", color: Theme.ketchupText)
            }
            .foregroundStyle(Theme.ink)
            HStack(spacing: 18) {
                Stamp("Confirmed")
                Stamp("Maybe", color: Theme.inkSoft, tilt: 3)
            }
            .padding(.vertical, 4)
        }
    }

    private var people: some View {
        section("People", kicker: "Monogram, personColor(name:)") {
            HStack(spacing: 10) {
                ForEach(["Maya", "Jordan", "Priya", "Sam", "Theo", "David"], id: \.self) { name in
                    VStack(spacing: 6) {
                        Monogram(name: name, size: 44)
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.personColor(name: name))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(Theme.people.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color)
                        .frame(height: 28)
                }
            }
            caption("brick, teal, plum, ochre, forest, navy, rose, slate")
        }
    }

    private var paper: some View {
        section("Paper", kicker: "paperCard, Ticket, receiptCard") {
            VStack(alignment: .leading, spacing: 6) {
                Kicker("For you")
                Text("Confirm you're coming by Thursday noon, or your Hearthstone spot goes to Alex.")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
            }
            .paperCard()

            Ticket {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Sat, Nov 7")
                    Text("Drive to Keystone")
                        .font(.serif(.title3))
                        .foregroundStyle(Theme.ink)
                    Text("6:00 AM · Maya's place")
                        .font(.mono(.subheadline))
                        .foregroundStyle(Theme.inkSoft)
                }
            } stub: {
                Stamp("Confirmed")
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Kicker("Who owes what")
                checkRow("You → Maya", "Airbnb", "$90.00")
                checkRow("You → Jordan", "Gas", "$20.00")
                checkRow("Sam → Theo", "Tickets", "$45.00")
                Line()
                    .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                HStack {
                    Text("You owe").font(.headline)
                    Spacer()
                    Text("$110.00").font(.mono(.headline, weight: .bold)).marked()
                }
                .foregroundStyle(Theme.ink)
            }
            .receiptCard()
        }
    }

    private var colors: some View {
        section("Colors", kicker: "Theme tokens, light / dark") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(swatch.color)
                            .frame(height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.rule, lineWidth: 1)
                            }
                        Text(swatch.name).font(.mono(.footnote, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(swatch.hex).font(.mono(.caption2)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    private struct Swatch {
        let name: String
        let color: Color
        let hex: String
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "cream", color: Theme.cream, hex: "FBF5EA / 17120F"),
        Swatch(name: "card", color: Theme.card, hex: "FFFDF8 / 231C17"),
        Swatch(name: "rule", color: Theme.rule, hex: "EADFCC / 3A302A"),
        Swatch(name: "ink", color: Theme.ink, hex: "2A1E19 / F6EEE2"),
        Swatch(name: "inkSoft", color: Theme.inkSoft, hex: "74655A / B3A595"),
        Swatch(name: "inkFaint", color: Theme.inkFaint, hex: "A99A8C / 7A6C60"),
        Swatch(name: "onInk", color: Theme.onInk, hex: "FFF8EE / 17120F"),
        Swatch(name: "ketchup", color: Theme.ketchup, hex: "D7372B / E8473A"),
        Swatch(name: "ketchupText", color: Theme.ketchupText, hex: "B22A20 / FF7B6B"),
        Swatch(name: "onKetchup", color: Theme.onKetchup, hex: "FFF8EE / FFF8EE"),
        Swatch(name: "mustard", color: Theme.mustard, hex: "F3B33D / E9A92F"),
        Swatch(name: "onMustard", color: Theme.onMustard, hex: "2A1E19 / 17120F"),
        Swatch(name: "pickle", color: Theme.pickle, hex: "4F7A3A / 8CC07A"),
    ]

    // MARK: Pieces

    private func section<Content: View>(_ title: String, kicker: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(kicker, color: Theme.ketchupText)
                Text(title)
                    .font(.serif(.title2))
                    .foregroundStyle(Theme.ink)
            }
            content()
        }
    }

    private func styleRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            caption(label)
            HStack(spacing: 10) { content() }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
    }

    private func iconIdea(paper: UInt32, drop: UInt32, shine: UInt32) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: UIColor(hex: paper)))
            KetchupDrop()
                .fill(Color(uiColor: UIColor(hex: drop)))
                .padding(12)
            DropShine()
                .fill(Color(uiColor: UIColor(hex: shine)).opacity(0.9))
                .padding(12)
        }
        .frame(width: 96, height: 96)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        }
    }

    private func checkRow(_ who: String, _ what: String, _ amount: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(who).font(.body.weight(.semibold))
            Text(what).font(.subheadline).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(amount).font(.mono(.body))
        }
        .foregroundStyle(Theme.ink)
    }
}

/// A horizontal line through the middle of its frame, for dashed rules.
nonisolated private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
#endif
