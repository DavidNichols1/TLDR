package com.vibetemp.ketchup.data.realtime

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * The hand-rolled WebSocket client against a tiny server on localhost
 * (plain ws://, so no certificates): the upgrade, masked client frames,
 * every length encoding, fragments, ping and close. No network.
 */
class WebSocketTest {

    @Test
    fun acceptKeyIsTheRfcExample() {
        // RFC 6455 section 1.3.
        assertEquals("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", WebSocketFrames.accept("dGhlIHNhbXBsZSBub25jZQ=="))
    }

    @Test
    fun clientFramesAreMaskedWithEveryLengthForm() {
        for (size in listOf(0, 5, 125, 126, 300, 65_535, 65_536, 70_000)) {
            val payload = ByteArray(size) { (it % 251).toByte() }
            val mask = byteArrayOf(0x12, 0x34, 0x56, 0x78)
            val frame = WebSocketFrames.encode(WebSocketFrames.OP_TEXT, payload, mask)
            assertEquals(0x81, frame[0].toInt() and 0xFF)
            assertTrue("masked", frame[1].toInt() and 0x80 != 0)
            val decoded = WebSocketFrames.read(ByteArrayInputStream(frame))!!
            assertTrue(decoded.fin)
            assertEquals(WebSocketFrames.OP_TEXT, decoded.opcode)
            assertArrayEquals("size $size", payload, decoded.payload)
        }
    }

    @Test
    fun talksToAServer() {
        val server = TestServer()
        val socket = SocketConnector.connect("ws://127.0.0.1:${server.port}/realtime/v1/websocket?apikey=k&vsn=1.0.0")
        try {
            assertEquals("GET /realtime/v1/websocket?apikey=k&vsn=1.0.0 HTTP/1.1", server.requestLine.poll(5, TimeUnit.SECONDS))

            // Client to server: masked text.
            assertTrue(socket.send("""{"event":"phx_join"}"""))
            assertEquals("""{"event":"phx_join"}""", server.received.poll(5, TimeUnit.SECONDS))

            // Server to client: short, 16-bit and 64-bit lengths, then a message in three fragments.
            server.sendText("hello")
            assertEquals("hello", socket.receive())
            val medium = "m".repeat(300)
            server.sendText(medium)
            assertEquals(medium, socket.receive())
            val long = "é".repeat(40_000) // 80,000 bytes of UTF-8
            server.sendText(long)
            assertEquals(long, socket.receive())
            server.sendFrame(fin = false, opcode = WebSocketFrames.OP_TEXT, payload = "{\"a\":".toByteArray())
            server.sendFrame(fin = false, opcode = WebSocketFrames.OP_CONTINUATION, payload = "\"b".toByteArray())
            server.sendFrame(fin = true, opcode = WebSocketFrames.OP_CONTINUATION, payload = "c\"}".toByteArray())
            assertEquals("{\"a\":\"bc\"}", socket.receive())

            // A ping gets its pong while the client waits for the next message.
            server.sendFrame(fin = true, opcode = WebSocketFrames.OP_PING, payload = "beat".toByteArray())
            server.sendText("after ping")
            assertEquals("after ping", socket.receive())
            assertEquals("pong:beat", server.received.poll(5, TimeUnit.SECONDS))

            // The server closes: receive says so, and sends stop working.
            server.sendFrame(fin = true, opcode = WebSocketFrames.OP_CLOSE, payload = byteArrayOf(0x03, 0xE8.toByte()))
            assertNull(socket.receive())
            assertFalse(socket.send("too late"))
        } finally {
            socket.close()
            server.stop()
        }
    }

    @Test
    fun aDroppedConnectionEndsReceive() {
        val server = TestServer()
        val socket = SocketConnector.connect("ws://127.0.0.1:${server.port}/")
        server.dropClient()
        assertNull(socket.receive())
        socket.close()
        server.stop()
    }

    @Test
    fun aBadHandshakeIsRefused() {
        val output = ByteArrayOutputStream()
        val wrongAccept = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: nope\r\n\r\n"
        try {
            WebSocketFrames.handshake(ByteArrayInputStream(wrongAccept.toByteArray()), output, "/", "example.com", key = "dGhlIHNhbXBsZSBub25jZQ==")
            fail("A wrong accept key must fail")
        } catch (e: IOException) {
            assertTrue(e.message!!.contains("didn't match"))
        }
        val request = output.toString(Charsets.US_ASCII.name())
        assertTrue(request.startsWith("GET / HTTP/1.1\r\nHost: example.com\r\n"))
        assertTrue(request.contains("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"))
        assertTrue(request.contains("Sec-WebSocket-Version: 13\r\n"))
        assertTrue(request.endsWith("\r\n\r\n"))

        val forbidden = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
        try {
            WebSocketFrames.handshake(ByteArrayInputStream(forbidden.toByteArray()), ByteArrayOutputStream(), "/", "example.com")
            fail("A 403 must fail")
        } catch (e: IOException) {
            assertTrue(e.message!!.contains("403"))
        }
    }

    @Test
    fun aGoodHandshakeLeavesTheFirstFrameUnread() {
        val key = "dGhlIHNhbXBsZSBub25jZQ=="
        val answer = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: ${WebSocketFrames.accept(key)}\r\n\r\n"
        val firstFrame = byteArrayOf(0x81.toByte(), 0x02, 'h'.code.toByte(), 'i'.code.toByte())
        val input = ByteArrayInputStream(answer.toByteArray() + firstFrame)
        WebSocketFrames.handshake(input, ByteArrayOutputStream(), "/", "example.com", key = key)
        assertEquals("hi", String(WebSocketFrames.read(input)!!.payload))
    }

    /**
     * One client at a time on a free localhost port: answers the upgrade,
     * then queues what the client sends (pongs as "pong:<payload>").
     */
    private class TestServer {
        private val server = ServerSocket(0)
        val port: Int = server.localPort
        val requestLine = LinkedBlockingQueue<String>()
        val received = LinkedBlockingQueue<String>()

        @Volatile
        private var output: OutputStream? = null

        @Volatile
        private var client: java.net.Socket? = null
        private val ready = LinkedBlockingQueue<Boolean>()

        init {
            thread(isDaemon = true) {
                val socket = server.accept()
                client = socket
                val input = socket.getInputStream()
                val out = socket.getOutputStream()
                val head = readHead(input)
                val lines = head.split("\r\n")
                requestLine.put(lines.first())
                val key = lines.first { it.lowercase().startsWith("sec-websocket-key:") }.substringAfter(':').trim()
                out.write(
                    ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                        "Sec-WebSocket-Accept: ${WebSocketFrames.accept(key)}\r\n\r\n").toByteArray(),
                )
                out.flush()
                output = out
                ready.put(true)
                while (true) {
                    val frame = try {
                        WebSocketFrames.read(input)
                    } catch (e: IOException) {
                        null
                    } ?: break
                    when (frame.opcode) {
                        WebSocketFrames.OP_TEXT -> received.put(String(frame.payload))
                        WebSocketFrames.OP_PONG -> received.put("pong:" + String(frame.payload))
                        WebSocketFrames.OP_CLOSE -> break
                    }
                }
            }
        }

        private fun out(): OutputStream {
            ready.poll(5, TimeUnit.SECONDS)?.let { ready.put(it) }
            return output ?: error("No client")
        }

        fun sendText(text: String) = sendFrame(true, WebSocketFrames.OP_TEXT, text.toByteArray())

        /** An unmasked server frame. */
        fun sendFrame(fin: Boolean, opcode: Int, payload: ByteArray) {
            val bytes = ByteArrayOutputStream()
            bytes.write((if (fin) 0x80 else 0) or opcode)
            when {
                payload.size < 126 -> bytes.write(payload.size)
                payload.size <= 0xFFFF -> {
                    bytes.write(126)
                    bytes.write(payload.size ushr 8)
                    bytes.write(payload.size and 0xFF)
                }
                else -> {
                    bytes.write(127)
                    for (shift in 56 downTo 0 step 8) bytes.write((payload.size.toLong() ushr shift and 0xFF).toInt())
                }
            }
            bytes.write(payload)
            val out = out()
            out.write(bytes.toByteArray())
            out.flush()
        }

        fun dropClient() {
            out()
            client?.close()
        }

        fun stop() {
            runCatching { client?.close() }
            runCatching { server.close() }
        }

        private fun readHead(input: InputStream): String {
            val bytes = ByteArrayOutputStream()
            while (!bytes.toString().endsWith("\r\n\r\n")) {
                val b = input.read()
                if (b == -1) break
                bytes.write(b)
            }
            return bytes.toString().removeSuffix("\r\n\r\n")
        }
    }
}
