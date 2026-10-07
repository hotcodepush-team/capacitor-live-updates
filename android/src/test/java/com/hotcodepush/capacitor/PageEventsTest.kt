package com.hotcodepush.capacitor

import com.getcapacitor.JSObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Which page an event reaches: the one that runs, or the one a load the SDK started brings. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PageEventsTest {
    private val notified = mutableListOf<Triple<String, String, Boolean>>()
    private val pageEvents = PageEvents { eventName, data, retainUntilConsumed -> notified += Triple(eventName, data.getString("releaseId") ?: "", retainUntilConsumed) }

    @Test
    fun shouldDeliverAnEventToThePageThatRunsWhenNoLoadIsPending() {
        pageEvents.deliver("updateAvailable", event("r2"), retainUntilConsumed = false)

        assertEquals(listOf(Triple("updateAvailable", "r2", false)), notified)
    }

    @Test
    fun shouldHoldEveryEventForTheNextPageAndRetainItThereWhenALoadIsPending() {
        pageEvents.holdUntilNextPage()
        pageEvents.deliver("rolledBack", event("r2"), retainUntilConsumed = true)
        pageEvents.deliver("updateAvailable", event("r3"), retainUntilConsumed = false)
        assertEquals(emptyList<Triple<String, String, Boolean>>(), notified)

        pageEvents.releaseToPage()

        assertEquals(listOf(Triple("rolledBack", "r2", true), Triple("updateAvailable", "r3", true)), notified)
        assertFalse(pageEvents.isPageLoadPending)
    }

    private fun event(releaseId: String) = JSObject().put("releaseId", releaseId)
}
