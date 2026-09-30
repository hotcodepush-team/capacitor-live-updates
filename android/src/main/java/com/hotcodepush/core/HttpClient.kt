package com.hotcodepush.core

import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

data class HttpResponse(val status: Int, val headers: Map<String, String>, val body: ByteArray) {
    fun header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
}

/** The two HTTP shapes the core needs: a small GET and a large download that resumes. */
interface HttpClient {
    suspend fun get(url: String, headers: Map<String, String>): HttpResponse

    /** Downloads to the file, appending from its current size with a `Range` request when it exists. */
    suspend fun download(url: String, file: File, progress: (Long, Long) -> Unit)
}

class OkHttpClientAdapter(private val client: OkHttpClient = sharedClient) : HttpClient {
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        val request = Request.Builder().url(url).apply { headers.forEach { (name, value) -> header(name, value) } }.build()
        client.newCall(request).execute().use { response ->
            val responseHeaders = response.headers.names().associateWith { response.headers[it] ?: "" }
            return HttpResponse(response.code, responseHeaders, response.body.bytes())
        }
    }

    override suspend fun download(url: String, file: File, progress: (Long, Long) -> Unit) {
        val existing = if (file.isFile) file.length() else 0L
        val request = Request.Builder().url(url).apply { if (existing > 0) header("Range", "bytes=$existing-") }.build()
        client.newCall(request).execute().use { response ->
            if (response.code != 200 && response.code != 206) throw DownloadFailure.DownloadFailed("HTTP ${response.code} for ${url.substringAfterLast('/')}")
            file.parentFile?.mkdirs()
            val append = response.code == 206 && existing > 0
            val total = existing.takeIf { append }?.plus(response.body.contentLength()) ?: response.body.contentLength()
            var written = if (append) existing else 0L
            file.outputStream().use { output ->
                if (append) file.appendBytes(ByteArray(0))
                response.body.byteStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        written += read
                        progress(written, total)
                    }
                }
            }
        }
    }

    companion object {
        /** One client per process, as OkHttp asks: its pools and threads outlive every activity. */
        private val sharedClient: OkHttpClient by lazy { OkHttpClient.Builder().connectTimeout(30, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build() }
    }
}
