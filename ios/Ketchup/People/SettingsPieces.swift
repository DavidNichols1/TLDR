//
//  SettingsPieces.swift
//  Ketchup
//
//  What Settings is built from: a titled section of rows on one paper
//  card, and the row itself (an icon, a label, maybe a value). Other
//  screens with a list of choices (Blocked people, People) use them too.
//

import SwiftUI

/// Width of a row's icon column at the default text size.
private let iconColumn: CGFloat = 24

/// A titled group of rows on one paper card, hairlines between them. A row
/// that draws nothing (an empty slot) takes no room and gets no hairline,
/// and a section with no rows at all doesn't show, title included.
struct SettingsSection<Content: View>: View {
    let title: String
    var kicker: String?
    var footer: String?
    let content: Content

    init(_ title: String, kicker: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.kicker = kicker
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { rows in
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    // The kicker goes under the title when both don't fit on a line.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            SectionTitle(title)
                            if let kicker { Kicker(kicker) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            SectionTitle(title)
                            if let kicker { Kicker(kicker) }
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            row
                            if row.id != rows.last?.id {
                                SettingsHairline()
                            }
                        }
                    }
                    .paperCard(padding: 0)
                    if let footer {
                        Text(footer)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The rule between two rows, starting where the row's label starts.
struct SettingsHairline: View {
    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = iconColumn

    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
            .padding(.leading, 16 + icon + 12)
    }
}

/// One row: an icon, a label, an optional value on the right, then
/// whatever the row adds (a spinner, a check) and a chevron for rows that
/// open a page. A `detail` goes on its own line under the label, for a long
/// label with a status ("Nothing saved"). `destructive` turns the label and
/// icon ketchup red (Delete account). Use it as a Button's or a
/// NavigationLink's label with `.buttonStyle(.pressable)`, or on its own
/// for a row that only shows something.
struct SettingsRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    var value: String?
    var detail: String?
    var destructive = false
    var chevron = false
    let accessory: Accessory

    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = iconColumn
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String, value: String? = nil, detail: String? = nil,
         destructive: Bool = false, chevron: Bool = false,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.detail = detail
        self.destructive = destructive
        self.chevron = chevron
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(destructive ? Theme.ketchupText : Theme.inkSoft)
                .frame(width: icon)
                .accessibilityHidden(true)
            // Big text puts the value under the label instead of squeezing both.
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(destructive ? Theme.ketchupText : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)
                if !stacked { Spacer(minLength: 0) }
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(stacked ? nil : 1)
                        .truncationMode(.middle)
                }
            }
            accessory
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
