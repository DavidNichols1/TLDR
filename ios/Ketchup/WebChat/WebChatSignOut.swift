//
//  WebChatSignOut.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. Settings' "Sign out of Instagram in Ketchup"
//  (and Snapchat): forgets what one source's sites saved in Ketchup's web
//  views on this iPhone (cookies, storage, caches, service workers), so the
//  next visit starts at their sign-in page. Only that source's sites: the
//  other one stays signed in, and the account itself isn't touched.
//

import WebKit

extension WebChatSource {
    /// Something from this source's sites is saved in Ketchup's web views.
    func hasSavedData() async -> Bool {
        !(await savedRecords()).isEmpty
    }

    /// Forgets everything this source's sites saved, then tells its page, if
    /// it's open, to start over (`webChatForgotten`).
    func forgetSavedData() async {
        let records = await savedRecords()
        if !records.isEmpty {
            await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                          for: records)
        }
        NotificationCenter.default.post(name: .webChatForgotten, object: id)
    }

    /// The web views all use the default store (WebChatBrowser). A record is
    /// named for its site ("instagram.com"), so match it to `domains`.
    private func savedRecords() async -> [WKWebsiteDataRecord] {
        let all = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        return all.filter { record in
            let site = record.displayName.lowercased()
            return domains.contains { site == $0 || site.hasSuffix("." + $0) }
        }
    }
}

extension Notification.Name {
    /// Posted with a source's `id` once its saved data is gone, so its page
    /// can go back to the start (the sign-in page, now).
    static let webChatForgotten = Notification.Name("ketchup.webChatForgotten")
}
