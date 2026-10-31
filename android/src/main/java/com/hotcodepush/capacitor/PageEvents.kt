package com.hotcodepush.capacitor

import com.getcapacitor.JSObject

// From a load the SDK starts until its page begins, events are held for that page, so the page being replaced never gets them.
// Use on the main thread only.
class PageEvents(private val notifyListeners: (eventName: String, data: JSObject, retainUntilConsumed: Boolean) -> Unit) {
    private val heldEvents = mutableListOf<Pair<String, JSObject>>()

    private var isPageLoadPending = false

    fun holdUntilNextPage() {
        isPageLoadPending = true
    }

    fun deliver(eventName: String, data: JSObject, retainUntilConsumed: Boolean) {
        if (isPageLoadPending) heldEvents += eventName to data else notifyListeners(eventName, data, retainUntilConsumed)
    }

    // By now, Capacitor has dropped the listeners of the previous page.
    fun releaseToPage() {
        isPageLoadPending = false
        val events = heldEvents.toList()
        heldEvents.clear()
        events.forEach { (eventName, data) -> notifyListeners(eventName, data, true) }
    }
}
