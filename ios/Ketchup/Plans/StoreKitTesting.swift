//
//  StoreKitTesting.swift
//  Ketchup
//
//  DEBUG simulator builds only. `-storekitTest YES` runs the app against
//  Ketchup.storekit, Xcode's local StoreKit test, without Xcode attached:
//
//    SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks \
//      xcrun simctl launch <udid> com.vibetemp.ketchup -storekitTest YES -screen paywall
//
//  The scheme's StoreKit configuration only applies to runs started from
//  Xcode, so this loads StoreKitTest's SKTestSession from the simulator's
//  developer frameworks and starts it on the bundled file, with no
//  purchases yet. SKTestSession asks XCTest which app it's testing, so
//  XCTest has to be findable: that's the framework path above (what Xcode
//  sets when it runs tests). Without it this prints why and does nothing.
//  Purchases are free and signed by Xcode, not Apple: the server takes them
//  only while STOREKIT_XCODE_TEST=true.
//
//  The last transaction's JWS goes to tmp/storekit-test-last.jws in the
//  app's container, so the server's check can be run on a real one
// (`deno test` covers the rules).
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import ObjectiveC

enum StoreKitTesting {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "storekitTest") }

    private static var session: NSObject?

    static func startIfAsked() {
        guard isOn, session == nil else { return }
        // SKTestSession aborts the app if it can't load XCTest from here.
        guard dlopen("/System/Library/Frameworks/XCTest.framework/XCTest", RTLD_NOW) != nil else {
            print("[storekit-test] XCTest isn't findable: launch with SIMCTL_CHILD_DYLD_FRAMEWORK_PATH (StoreKitTesting.swift)")
            return
        }
        guard dlopen("/Developer/Library/Frameworks/StoreKitTest.framework/StoreKitTest", RTLD_NOW) != nil,
              let type = NSClassFromString("SKTestSession") as? NSObject.Type,
              let file = Bundle.main.url(forResource: "Ketchup", withExtension: "storekit") else {
            print("[storekit-test] couldn't load StoreKitTest or Ketchup.storekit")
            return
        }
        // -[SKTestSession initWithContentsOfURL:error:], through the runtime:
        // StoreKitTest isn't linked into the app.
        typealias Initializer = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let selector = NSSelectorFromString("initWithContentsOfURL:error:")
        guard let method = class_getInstanceMethod(type, selector),
              let blank = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return }
        let initialize = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
        var error: NSError?
        guard let made = initialize(blank, selector, file as NSURL, &error) as? NSObject else {
            print("[storekit-test] SKTestSession refused Ketchup.storekit: \(error?.localizedDescription ?? "no reason")")
            return
        }
        made.perform(NSSelectorFromString("resetToDefaultState"))
        made.perform(NSSelectorFromString("clearTransactions"))
        // `-storekitDialogs NO`: buy without StoreKit's confirmation sheet.
        let defaults = UserDefaults.standard
        let dialogs = defaults.object(forKey: "storekitDialogs") == nil || defaults.bool(forKey: "storekitDialogs")
        made.setValue(!dialogs, forKey: "disableDialogs")
        made.setValue(false, forKey: "askToBuyEnabled")
        session = made
        print("[storekit-test] on, with Ketchup.storekit and no purchases")
    }

    /// Keeps the last transaction's JWS for the server-side check.
    static func keep(_ jws: String) {
        guard isOn else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("storekit-test-last.jws")
        try? Data(jws.utf8).write(to: url, options: .atomic)
        print("[storekit-test] kept a transaction, \(jws.count) characters")
    }
}
#endif
