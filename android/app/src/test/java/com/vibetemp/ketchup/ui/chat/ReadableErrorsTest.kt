package com.vibetemp.ketchup.ui.chat

import com.vibetemp.ketchup.data.ApiException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.ConnectException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLHandshakeException

/** What sign-in and the chat say when the phone can't reach Ketchup at all. */
class ReadableErrorsTest {

    @Test
    fun eachKindOfNetworkFailureSaysWhy() {
        assertTrue(ChatModel.readable(UnknownHostException("Unable to resolve host")).startsWith("Couldn't find Cetchup's server."))
        assertTrue(ChatModel.readable(SSLHandshakeException("Chain validation failed")).startsWith("Couldn't make a secure connection"))
        assertTrue(ChatModel.readable(SocketTimeoutException("timeout")).startsWith("Cetchup took too long"))
        assertTrue(ChatModel.readable(SocketException("socket failed: EPERM (Operation not permitted)")).startsWith("Android isn't letting Cetchup"))
        assertEquals("Couldn't reach Cetchup. Check your connection and try again.", ChatModel.readable(ConnectException("Failed to connect")))
    }

    @Test
    fun theServersOwnWordsStillWin() {
        assertEquals("Email rate limit exceeded", ChatModel.readable(ApiException("Email rate limit exceeded", status = 429)))
        assertEquals("Something went wrong. Try again.", ChatModel.readable(IllegalStateException()))
    }
}
