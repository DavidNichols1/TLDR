//
//  WebReadCheck.swift
//  Ketchup
//
//  DEBUG only. Offline checks of the web-chat readers on the synthetic test
//  threads (Instagram/Fixture/, Snapchat/Fixture/, made-up people), run
//  from launch arguments on `-screen web-instagram` or `web-snapchat`:
//
//    -readTest 10          reads the last 10, as the menu does
//    -followTest YES       "Until I stop scrolling" while a pretend person
//                          scrolls the test page ("up 8, down 2, up 120" by
//                          default, or moves of your own)
//    -webFixture <file>    another test thread, like ig-thread-fixture-virtual
//
//  The read is compared with the thread's `.expected.json`, and the console
//  gets counts only, never text or names:
//  `[instagram] follow check: 88 of 88 match the test thread's newest 88 in order, ...`.
//  The pretend person is test code: it scrolls the test page's own scroller
//  from a content world of its own, never the reader's, and only ever on a
//  test thread.
//

#if DEBUG
import SwiftUI
import WebKit

enum WebReadCheck {
    /// Waits for the test page to load and settle.
    static func loaded(_ browser: WebChatBrowser) async {
        for _ in 0..<100 {
            if browser.isThread, !browser.isLoading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(800))
    }

    /// "up 8, down 2, up 120" as one step each: -1 up, +1 down. YES is that plan.
    static func moves(_ plan: String) -> [Int] {
        let text = plan == "YES" || plan == "1" ? "up 8, down 2, up 120" : plan
        var out: [Int] = []
        for part in text.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let n = Int(words[1]), n >= 0 else { continue }
            out += Array(repeating: words[0] == "down" ? 1 : -1, count: n)
        }
        return out
    }

    private static let person = WKContentWorld.world(name: "KetchupDebugPerson")

    /// A person scrolling the test thread: a second in, then 0.6 of a screen
    /// every half second. Four ups in a row that go nowhere is the top of
    /// the thread: the rest of that run of ups is skipped.
    static func person(_ browser: WebChatBrowser, moves: [Int]) async {
        guard browser.fixture != nil else { return }
        let script = """
        const sc = [...document.querySelectorAll('*')]
          .filter((el) => /(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight + 8)
          .sort((a, b) => (b.scrollHeight - b.clientHeight) - (a.scrollHeight - a.clientHeight))[0];
        if (!sc) return 0;
        const before = sc.scrollTop;
        sc.scrollTop = before + direction * Math.round(sc.clientHeight * 0.6);
        return Math.abs(sc.scrollTop - before);
        """
        try? await Task.sleep(for: .seconds(1))
        var ups = 0, downs = 0, stuck = 0, next = 0
        while next < moves.count, browser.fixture != nil {
            let direction = moves[next]
            let went = (try? await browser.webView.callAsyncJavaScript(script, arguments: ["direction": direction],
                                                                       in: nil, contentWorld: person) as? NSNumber)?.doubleValue ?? 0
            if direction < 0 { ups += 1 } else { downs += 1 }
            stuck = direction < 0 && went < 1 ? stuck + 1 : 0
            next += 1
            if stuck >= 4 {
                while next < moves.count, moves[next] < 0 { next += 1 }
                stuck = 0
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        print("[\(browser.source.id)] the pretend person scrolled \(ups) up and \(downs) down")
    }

    private struct Expected: Decodable {
        struct Message: Decodable {
            let sender: String
            let isMe: Bool
            let text: String
        }
        let messages: [Message]
    }

    /// Compares a read with the test thread's ground truth, oldest first:
    /// a Last N read with its newest N, a follow with all of it (or its
    /// newest part, if it stopped early). Counts only.
    static func compare(_ thread: WebThread, fixture: WebChatSource.Fixture?, last: Int?) {
        guard let fixture, let url = Bundle.main.url(forResource: "\(fixture.file).expected", withExtension: "json"),
              let data = try? Data(contentsOf: url), let truth = try? JSONDecoder().decode(Expected.self, from: data) else { return }
        func plain(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let all = truth.messages.map { $0.isMe ? "me|\(plain($0.text))" : "\(plain($0.sender))|\(plain($0.text))" }
        let got = thread.messages.map { $0.isMe ? "me|\(plain($0.text))" : "\(plain($0.sender))|\(plain($0.text))" }
        let want = Array(all.suffix(last ?? all.count))
        let newest = Array(want.suffix(got.count))
        let inOrder = zip(newest, got.suffix(newest.count)).filter { $0 == $1 }.count
        var left = Dictionary(all.map { ($0, 1) }, uniquingKeysWith: +)
        var repeated = 0
        for key in got {
            if let n = left[key], n > 0 { left[key] = n - 1 } else { repeated += 1 }
        }
        let what = last.map { "Last \($0) check" } ?? "follow check"
        print("[\(thread.source.id)] \(what): \(inOrder) of \(got.count) match the test thread's newest \(newest.count) in order, "
              + "\(got.count) of its \(want.count) read, \(repeated) repeated or not in it")
    }
}
#endif
