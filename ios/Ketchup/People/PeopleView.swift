//
//  PeopleView.swift
//  Ketchup
//
//  Your people: everyone you've added from a profile, by name, with how
//  many chats you share. Tap one for their profile. They're who New chat
//  offers to add, so a chat with them needs no code. From Settings; the
//  You tab shows the same list (PeopleList).
//

import SwiftUI

struct PeopleView: View {
    private var store: PeopleStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(count)
                    Text("Your people")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Add people from their profile in any chat you share. They're on your list when you start a new chat, so they're in without a code.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if store.contacts.isEmpty {
                    if store.contactsLoaded { NoPeopleCard() } else { ProgressView().tint(Theme.inkSoft).frame(maxWidth: .infinity) }
                } else {
                    PeopleList(contacts: store.contacts)
                }

                NavigationLink {
                    InviteView()
                } label: {
                    Label("Invite friends", systemImage: "paperplane")
                }
                .buttonStyle(.outline)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.cream)
        .navigationTitle("Your people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The big header names the page; the bar keeps just Back.
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
        .motion(value: store.contacts.map(\.id))
        .task { await store.loadContacts(force: true) }
    }

    private var count: String {
        guard store.contactsLoaded, !store.contacts.isEmpty else { return "People" }
        return store.contacts.count == 1 ? "1 person" : "\(store.contacts.count) people"
    }
}

/// Your people on one paper card: each one's photo, name and how many chats
/// you share, with a chevron to their profile. Your people and the You tab.
struct PeopleList: View {
    let contacts: [Contact]

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            ForEach(contacts) { contact in
                NavigationLink {
                    ProfileView(person: contact.person)
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: contact.displayName, path: contact.avatarPath, size: avatarSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.displayName)
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            Text(Self.sharedLine(contact.sharedChats))
                                .font(.mono(.caption2))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkFaint)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.pressable)
                .transition(.opacity)
                if contact.id != contacts.last?.id {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: 1)
                        .padding(.leading, avatarSize + 12)
                }
            }
        }
        .paperCard(padding: 14)
    }

    static func sharedLine(_ chats: Int) -> String {
        switch chats {
        case 0: "No chats together now"
        case 1: "In 1 chat with you"
        default: "In \(chats) chats with you"
        }
    }
}

/// Nobody yet: a quiet card that says where Add lives.
struct NoPeopleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No one yet")
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
            Text("In a chat, tap someone's name for their profile, then Add to your people.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard(padding: 18)
    }
}

/// Your people as a list to pick from, for New chat: tap to add or take out.
struct PeoplePicker: View {
    let people: [Person]
    @Binding var picked: Set<UUID>

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            ForEach(people) { person in
                let on = picked.contains(person.id)
                Button {
                    if on { picked.remove(person.id) } else { picked.insert(person.id) }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: person.name, path: person.avatarPath, size: avatarSize)
                        Text(person.name)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(on ? .isSelected : [])
                .sensoryFeedback(.selection, trigger: on)
                if person.id != people.last?.id {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: 1)
                        .padding(.leading, avatarSize + 12)
                }
            }
        }
        .paperCard(padding: 14)
    }
}
