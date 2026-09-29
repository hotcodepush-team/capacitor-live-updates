package com.hotcodepush.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** One entry of a pack: the file's hash and its stored bytes, gzip as the bucket serves them. */
data class PackEntry(val sha256: String, val body: ByteArray)

class PackFormatException(message: String) : Exception(message)

/** Reads the pack format: an uncompressed ustar archive whose entries are named by their content hash. */
object PackReader {
    private const val BLOCK_SIZE = 512

    fun entries(bytes: ByteArray): List<PackEntry> = buildList { forEachEntry(ByteArrayInputStream(bytes)) { add(it) } }

    fun forEachEntry(input: InputStream, body: (PackEntry) -> Unit) {
        val header = ByteArray(BLOCK_SIZE)
        while (true) {
            val read = input.readFully(header)
            if (read < BLOCK_SIZE || header.all { it == 0.toByte() }) return
            val name = field(header, 0, 100)
            val size = field(header, 124, 12).toIntOrNull(8) ?: throw PackFormatException("Invalid size field")
            val content = ByteArray(size)
            if (input.readFully(content) < size) throw PackFormatException("Truncated pack")
            body(PackEntry(name, content))
            val padding = (BLOCK_SIZE - size % BLOCK_SIZE) % BLOCK_SIZE
            if (padding > 0 && input.readFully(ByteArray(padding)) < padding) throw PackFormatException("Truncated pack")
        }
    }

    private fun field(header: ByteArray, start: Int, length: Int): String {
        val end = (start until start + length).firstOrNull { header[it] == 0.toByte() } ?: (start + length)
        return String(header, start, end - start, Charsets.US_ASCII).trim()
    }

    private fun InputStream.readFully(buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val read = read(buffer, total, buffer.size - total)
            if (read < 0) break
            total += read
        }
        return total
    }
}

/** Writes the same format; the SDK only reads packs, the writer exists for the tests. */
object PackWriter {
    fun pack(entries: List<PackEntry>): ByteArray {
        val output = ByteArrayOutputStream()
        for (entry in entries) {
            val header = ByteArray(512)
            entry.sha256.toByteArray(Charsets.US_ASCII).copyInto(header, 0)
            "%011o".format(entry.body.size).toByteArray(Charsets.US_ASCII).copyInto(header, 124)
            for (index in 148 until 156) header[index] = 0x20
            val checksum = header.sumOf { it.toInt() and 0xff }
            ("%06o".format(checksum) + "\u0000").toByteArray(Charsets.US_ASCII).copyInto(header, 148)
            output.write(header)
            output.write(entry.body)
            output.write(ByteArray((512 - entry.body.size % 512) % 512))
        }
        output.write(ByteArray(1024))
        return output.toByteArray()
    }
}

/** Decodes the gzip bytes the bucket serves into the file's content. */
object Gzip {
    /** Gzip bytes carry the `1f 8b` magic; anything else is stored as it is. */
    fun isCompressed(bytes: ByteArray): Boolean = bytes.size >= 2 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte()

    fun decompressIfCompressed(bytes: ByteArray): ByteArray = if (isCompressed(bytes)) decompress(bytes) else bytes

    fun decompress(bytes: ByteArray): ByteArray = if (bytes.isEmpty()) bytes else GZIPInputStream(ByteArrayInputStream(bytes)).use { it.readBytes() }

    fun compress(bytes: ByteArray): ByteArray = ByteArrayOutputStream().also { output -> GZIPOutputStream(output).use { it.write(bytes) } }.toByteArray()
}
