package com.hotcodepush.core

/** The platform's key-value store, one string per key; `SharedPreferences` on Android, a map in tests. */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}
