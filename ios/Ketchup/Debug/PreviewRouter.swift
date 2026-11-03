//
//  PreviewRouter.swift
//  Ketchup
//
//  Which screen `-screen <name>` opens. `ai-` names belong to the Muse Spark
//  screens (AIPreviewScreen.swift), `web-` names to the web-chat screens
//  (WebChatPreviewScreen.swift), `design` is the component gallery,
//  Settings and the people screens are in PeoplePreviewScreen.swift, and
//  the rest are the chat screens (CorePreviewScreen.swift). `list` (or any
//  name that isn't a screen) shows every name, and tapping one opens it.
//

#if DEBUG
import SwiftUI

struct PreviewRouter: View {
    @State private var name: String

    init(name: String) {
        _name = State(initialValue: name)
    }

    /// Opens the list of screens.
    static let listName = "list"

    /// Every screen's `-screen` name, in the order the list shows them.
    static var names: [String] {
        [DesignGallery.name] + CorePreviewScreen.names + AIPreviewScreen.names + WebChatPreviewScreen.names
            + PeoplePreviewScreen.names
    }

    var body: some View {
        Group {
            if name == DesignGallery.name {
                DesignGallery()
            } else if name.hasPrefix("ai-"), AIPreviewScreen.names.contains(name) {
                AIPreviewScreen(name: name)
            } else if name.hasPrefix("web-"), WebChatPreviewScreen.names.contains(name) {
                WebChatPreviewScreen(name: name)
            } else if PeoplePreviewScreen.names.contains(name) {
                PeoplePreviewScreen(name: name)
            } else if CorePreviewScreen.names.contains(name) {
                CorePreviewScreen(name: name)
            } else {
                PreviewIndex(unknown: name == Self.listName ? nil : name) { name = $0 }
            }
        }
        .id(name)
    }
}

/// The list of `-screen` names. Tapping one opens it when `open` is set.
struct PreviewIndex: View {
    var unknown: String?
    var open: ((String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Offline preview")
                    Text("Pick a screen")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                    if let unknown {
                        Text("There's no screen called “\(unknown)”.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(PreviewRouter.names, id: \.self) { name in
                        Button {
                            open?(name)
                        } label: {
                            HStack {
                                Text(name).font(.mono(.body))
                                Spacer()
                                if open != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.pressable)
                        .disabled(open == nil)
                        if name != PreviewRouter.names.last { Divider().overlay(Theme.rule) }
                    }
                }
                .paperCard(padding: 14)
                Text("Launch with -screen <name>, and add -section <id> to scroll the design gallery.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
        }
        .background(Theme.cream)
    }
}
#endif
