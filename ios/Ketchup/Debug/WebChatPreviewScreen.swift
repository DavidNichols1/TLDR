//
//  WebChatPreviewScreen.swift
//  Ketchup
//
//  The web-chat screens offline, one per `-screen web-…` name, on the
//  synthetic threads in Instagram/Fixture/ and Snapchat/Fixture/ (made-up
//  people): the Instagram page on its thread, the first-visit card, the
//  catch-up while it reads, a finished one (a canned brief, not a Muse
//  Spark call), a failure, a source shown whole, and the Snapchat page on
//  its thread. No sign-in, no network. Sheets are shown full screen.
//

#if DEBUG
import SwiftUI

struct WebChatPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case instagram = "web-instagram"
        case intro = "web-intro"
        case reading = "web-reading"
        case brief = "web-brief"
        case error = "web-error"
        case quote = "web-quote"
        case snapchat = "web-snapchat"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()

    init(name: String) {
        self.name = name
        // For this launch only: the tabs open their fixture threads, and show
        // a first-visit card only on web-intro.
        var args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        // `-KetchupSnapchatFixture NO` keeps the real site instead.
        if args["KetchupInstagramFixture"] == nil { args["KetchupInstagramFixture"] = true }
        if args["KetchupSnapchatFixture"] == nil { args["KetchupSnapchatFixture"] = true }
        args["webchat.instagram.introSeen"] = name != Screen.intro.rawValue
        args["webchat.snapchat.introSeen"] = true
        UserDefaults.standard.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .instagram, .intro:
                WebChatTab(source: .instagram)
            case .reading:
                WebChatSheet(session: WebCatchUp(thread: Self.thread, readerName: Self.reader, brief: .loading,
                                                 answer: .idle, lastQuestion: ""))
            case .brief:
                WebChatSheet(session: WebCatchUp(thread: Self.thread, readerName: Self.reader, brief: .done(Self.brief),
                                                 answer: .idle, lastQuestion: ""))
            case .error:
                WebChatSheet(session: WebCatchUp(thread: Self.thread, readerName: Self.reader,
                                                 brief: .failed("Muse Spark is busy right now. Try again in a moment."),
                                                 answer: .idle, lastQuestion: ""))
            case .quote:
                WebQuoteCard(message: Self.thread.messages[84], source: .instagram)
            case .snapchat:
                WebChatTab(source: .snapchat)
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    private static let reader = "David"

    /// The fixture's ground truth, read back as the thread the reader returns.
    static var thread: WebThread {
        struct File: Decodable {
            let title: String
            let isGroup: Bool
            let messages: [WebMessage]
        }
        let url = Bundle.main.url(forResource: "ig-thread-fixture.expected", withExtension: "json")!
        let file = try! JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return WebThread(source: .instagram, title: file.title, isGroup: file.isGroup, messages: file.messages,
                         reachedStart: true, truncated: false, stats: nil)
    }

    /// Written by hand in catch-up-text's shape, refs as indexes into the fixture's 88 messages.
    static var brief: BriefResponse<CatchUp> {
        try! WebChatAPI.decode(Data(briefJSON.utf8))
    }

    private static let briefJSON = #"""
    {"kind":"catch_up","source":"instagram","cached":false,"model":"muse-spark-1.3","message_count":88,"latency_ms":17400,
     "result":{"tldr":"Breck is on: you leave Saturday at 6am from Jordan's, the Airbnb is $248 each by Friday, and Priya gets in Saturday around 9pm.",
      "for_you":[{"text":"Jordan asked if you're bringing the speaker.","refs":[84]},{"text":"Sam needs your boot size by tomorrow for the rental.","refs":[85]}],
      "plans":[{"title":"Drive to Breck","starts_at":"2026-11-07T06:00:00-07:00","ends_at":null,"all_day":false,"location":"Jordan's place","status":"confirmed","who":["Jordan","Maya","Sam","David"],"refs":[44,75]},
               {"title":"Dinner at The Rusty Gondola","starts_at":"2026-11-07T19:30:00-07:00","ends_at":null,"all_day":false,"location":"The Rusty Gondola","status":"confirmed","who":[],"refs":[53]}],
      "open_questions":[{"question":"David, are you bringing the speaker?","asked_by":"Jordan","refs":[84]}],
      "owes":[{"who":"David","owes_whom":"Maya","what":"$248 for the Airbnb, by Friday","refs":[23,71]}],
      "highlights":[{"text":"The trip became official","refs":[0]},{"text":"Garage has 2 spots, so both cars fit","refs":[63,64]}]}}
    """#
}
#endif
