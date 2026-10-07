#if canImport(Capacitor)
import Capacitor
import Foundation
import WebKit

/// The core's events for the page that runs: from a load the SDK starts until its page begins they are held for that page, so the
/// page being replaced never receives them, and each goes out retained until that page listens for it. Main thread only.
final class PageEvents {
    private weak var plugin: CAPPlugin?
    private var heldEvents: [(eventName: String, data: JSObject)] = []
    /// A load the SDK started has not begun its page yet.
    private(set) var isPageLoadPending = false

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

    /// A page began, after Capacitor dropped the listeners of the one before: the events held for it go out.
    func releaseToPage() {
        isPageLoadPending = false
        let events = heldEvents
        heldEvents = []
        for event in events {
            plugin?.notifyListeners(event.eventName, data: event.data, retainUntilConsumed: true)
        }
    }
}

/// Hears each page the WebView begins in its main frame, from a script that runs before the page's own, in a world the page cannot
/// reach; the message arrives after Capacitor reset its bridge for the navigation and before any call of the new page.
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
#endif
