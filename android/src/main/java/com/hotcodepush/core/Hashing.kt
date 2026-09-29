package com.hotcodepush.core

import java.security.MessageDigest

object Hashing {
    fun sha256Hex(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    fun sha256Hex(text: String): String = sha256Hex(text.toByteArray(Charsets.UTF_8))

    /** `sha256(key + '\0' + value)`, the form an attribute condition carries. */
    fun attributeHash(key: String, value: String): String = sha256Hex(key + "\u0000" + value)

    /** The rollout bucket: a stable hash of the device id and the release id into a hundred buckets. */
    fun rolloutBucket(deviceId: String, releaseId: String): Int {
        val digest = MessageDigest.getInstance("SHA-256").digest((deviceId + "\u0000" + releaseId).toByteArray(Charsets.UTF_8))
        val value = ((digest[0].toLong() and 0xff) shl 24) or ((digest[1].toLong() and 0xff) shl 16) or ((digest[2].toLong() and 0xff) shl 8) or (digest[3].toLong() and 0xff)
        return (value % 100).toInt()
    }
}
