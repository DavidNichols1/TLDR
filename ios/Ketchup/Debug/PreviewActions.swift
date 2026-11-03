//
//  PreviewActions.swift
//  Ketchup
//
//  DEBUG launch flags that act 1.2 s into a preview, as if tapped, to show
//  what changes at once and what comes back when the server says no:
//    -leave YES          leaves Breck Weekend (the inbox, `-screen home`)
//    -renameTo "Dave"    your name in Settings (`-screen settings`)
//    -serverRefuses YES  the pretend server says no after a moment
//

#if DEBUG
import SwiftUI

struct PreviewActions: ViewModifier {
    let app: AppModel

    func body(content: Content) -> some View {
        content.task {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "leave") || defaults.string(forKey: "renameTo") != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if let name = defaults.string(forKey: "renameTo") { app.renameNow(to: name) }
            if defaults.bool(forKey: "leave"), let chat = app.chat(PreviewData.breckId) { await app.leave(chat) }
        }
    }
}
#endif
