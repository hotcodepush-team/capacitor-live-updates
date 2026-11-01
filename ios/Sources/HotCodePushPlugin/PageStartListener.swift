import Foundation
import WebKit

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
