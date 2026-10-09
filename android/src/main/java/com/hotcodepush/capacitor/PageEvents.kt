package com.hotcodepush.capacitor

import com.getcapacitor.JSObject

/**
 * The core's events for the page that runs: from a load the SDK starts until its page begins they are held for that page, so the
 * page being replaced never receives them, and each goes out retained until that page listens for it. Main thread only.
 */
class PageEvents(private val notifyListeners: (eventName: String, data: JSObject, retainUntilConsumed: Boolean) -> Unit) {
    private val heldEvents = mutableListOf<Pair<String, JSObject>>()

    /** A load the SDK started has not begun its page yet. */
    private var isPageLoadPending = false

    fun holdUntilNextPage() {
        isPageLoadPending = true
    }

    fun deliver(eventName: String, data: JSObject, retainUntilConsumed: Boolean) {
        if (isPageLoadPending) heldEvents += eventName to data else notifyListeners(eventName, data, retainUntilConsumed)
    }

    /** A page began, after Capacitor dropped the listeners of the one before: the events held for it go out. */
    fun releaseToPage() {
        isPageLoadPending = false
        val events = heldEvents.toList()
        heldEvents.clear()
        events.forEach { (eventName, data) -> notifyListeners(eventName, data, true) }
    }
}
