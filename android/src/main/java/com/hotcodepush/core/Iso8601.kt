package com.hotcodepush.core

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Timestamps travel as ISO 8601 in UTC and live as epoch milliseconds. */
object Iso8601 {
    fun format(epochMillis: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis).truncatedTo(ChronoUnit.MILLIS))

    fun parse(value: String): Long = Instant.parse(value).toEpochMilli()

    fun parseOrNull(value: String?): Long? = value?.let { runCatching { parse(it) }.getOrNull() }
}
