package com.hotcodepush.core

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File
import java.nio.file.Files

class HttpClientTest {
    private val url = "https://files.test/apps/a/bundles/b2/pack"
    private val file = File(Files.createTempDirectory("hotcodepush-tests").toFile(), "b2.pack")

    @Test
    fun shouldStopADownloadPastItsMaximumAndDeleteTheFile() {
        val client = client { request -> response(request, 200, ByteArray(200_000)) }
        val failure = assertThrows(DownloadFailure::class.java) { runBlocking { client.download(url, file, 100_000) { _, _ -> } } }
        assertEquals(FailedReason.DOWNLOAD_FAILED, failure.reason)
        assertFalse(file.exists())
    }

    /** The real OkHttp client with the network replaced by the reply. */
    private fun client(reply: (Request) -> Response) = OkHttpClientAdapter(OkHttpClient.Builder().addInterceptor { chain -> reply(chain.request()) }.build())

    private fun response(request: Request, code: Int, body: ByteArray) = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("").body(body.toResponseBody()).build()
}
