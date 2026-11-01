import Capacitor
import Foundation

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
