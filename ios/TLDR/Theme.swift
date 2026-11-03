//
//  Theme.swift
//  TLDR
//
//  Two visual languages on purpose: the chat itself is plain iOS blue, and
//  everything Muse Spark produces wears the indigo → violet → pink gradient
//  with a sparkle, so in the demo video you can always tell what the AI did.
//

import SwiftUI

enum Theme {
    /// Normal chat UI (my bubbles, send button, badges).
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)

    // AI palette.
    static let indigo = Color(red: 0.31, green: 0.28, blue: 0.90)
    static let violet = Color(red: 0.55, green: 0.29, blue: 0.95)
    static let pink   = Color(red: 0.86, green: 0.36, blue: 0.80)

    static let aiGradient = LinearGradient(colors: [indigo, violet, pink],
                                           startPoint: .leading, endPoint: .trailing)
    static let aiDiagonal = LinearGradient(colors: [indigo, violet, pink],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    /// A faint wash behind AI cards.
    static let aiWash = LinearGradient(colors: [indigo.opacity(0.10), violet.opacity(0.08), pink.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

    static let aiSymbol = "sparkles"
    static let aiName = "Muse Spark"

    /// A stable color per person, for sender names and avatars.
    static func personColor(_ id: UUID) -> Color {
        let palette: [Color] = [.orange, .pink, .teal, .green, .purple, .red, .mint, .brown, .cyan, .indigo]
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Dates

extension Date {
    /// Inbox stamp: "7:41 PM", "Yesterday", "Mon", "Oct 28".
    var inboxStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// Day separator in a thread: "Today", "Yesterday", "Monday, Nov 2".
    var daySeparator: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
