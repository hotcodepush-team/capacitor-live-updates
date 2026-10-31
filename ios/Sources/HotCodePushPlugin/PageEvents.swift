import Capacitor
import Foundation
import WebKit

// From a load the SDK starts until its page begins, events are held for that page, so the page being replaced never gets them.
// Use on the main thread only.
final class PageEvents {
    private weak var plugin: CAPPlugin?
    private var heldEvents: [(eventName: String, data: JSObject)] = []
    private var isPageLoadPending = false

    init(plugin: CAPPlugin) {
        self.plugin = plugin
    }

    func holdUntilNextPage() {
        isPageLoadPending = true
    }

    func deliver(_ eventName: String, data: JSObject, retainUntilConsumed: Bool) {
        if isPageLoadPending {
            heldEvents.append((eventName, data))
        } else {
            plugin?.notifyListeners(eventName, data: data, retainUntilConsumed: retainUntilConsumed)
        }
    }

    // By now, Capacitor has dropped the listeners of the previous page.
    func releaseToPage() {
        isPageLoadPending = false
        let events = heldEvents
        heldEvents = []
        for event in events {
            plugin?.notifyListeners(event.eventName, data: event.data, retainUntilConsumed: true)
        }
    }
}

// The script runs in the main frame before the scripts of the page, in a content world the page cannot reach.
// Its message arrives after Capacitor resets the bridge for the navigation and before any call of the new page.
final class PageStartListener: NSObject, WKScriptMessageHandler {
    private static let messageName = "hotCodePushPageStart"

    private let onPageStart: (URL) -> Void

    private init(onPageStart: @escaping (URL) -> Void) {
        self.onPageStart = onPageStart
    }

    static func attach(to webView: WKWebView, onPageStart: @escaping (URL) -> Void) {
        let controller = webView.configuration.userContentController
        let world = WKContentWorld.defaultClient
        controller.add(PageStartListener(onPageStart: onPageStart), contentWorld: world, name: messageName)
        let source = "window.webkit.messageHandlers.\(messageName).postMessage(location.href)"
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let href = message.body as? String, let url = URL(string: href) else { return }
        onPageStart(url)
    }
}
