package com.vibetemp.ketchup.data.realtime

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLPeerUnverifiedException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * One open WebSocket that carries text. Blocking calls: Realtime runs them
 * on the IO dispatcher. The JVM tests swap in a fake.
 */
interface WebSocketConnection {
    /** Sends one text message. False once the socket is closed. */
    fun send(text: String): Boolean

    /** Waits for the next text message; null once the socket has closed. */
    fun receive(): String?

    /** Closes it (on a background thread, so it's safe from the main thread). Idempotent. */
    fun close()
}

/** Opens a WebSocket with the handshake done, or throws an IOException. Blocking. */
fun interface WebSocketConnector {
    fun connect(url: String): WebSocketConnection
}

/**
 * A small RFC 6455 client over a plain or TLS socket, so the app keeps no
 * networking dependency (the same choice as `SupabaseClient`): the HTTP
 * upgrade, masked client frames, ping and pong, fragmented messages, and
 * close. Enough for Supabase Realtime's JSON frames, nothing more.
 */
object SocketConnector : WebSocketConnector {
    private const val CONNECT_TIMEOUT_MS = 15_000

    /**
     * Realtime answers every heartbeat (sent each 25 s), so a minute of
     * silence means the connection is dead even if TCP hasn't noticed.
     */
    const val READ_TIMEOUT_MS = 60_000

    override fun connect(url: String): WebSocketConnection {
        val uri = URI(url)
        val secure = when (uri.scheme?.lowercase()) {
            "wss" -> true
            "ws" -> false
            else -> throw IOException("Not a WebSocket address.")
        }
        val host = uri.host ?: throw IOException("Not a WebSocket address.")
        val port = if (uri.port != -1) uri.port else if (secure) 443 else 80
        val raw = Socket()
        try {
            raw.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            raw.soTimeout = READ_TIMEOUT_MS
            val socket = if (secure) tls(raw, host, port) else raw
            val input = BufferedInputStream(socket.getInputStream())
            val output = socket.getOutputStream()
            val path = (uri.rawPath?.ifEmpty { "/" } ?: "/") + (uri.rawQuery?.let { "?$it" } ?: "")
            val hostHeader = if (uri.port == -1) host else "$host:$port"
            WebSocketFrames.handshake(input, output, path, hostHeader)
            return SocketWebSocket(socket, input, output)
        } catch (e: IOException) {
            runCatching { raw.close() }
            throw e
        }
    }

    /** TLS over [raw] with the system's trust store, SNI and a hostname check (SSLSocket doesn't check names itself). */
    private fun tls(raw: Socket, host: String, port: Int): Socket {
        val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
        val ssl = factory.createSocket(raw, host, port, true) as SSLSocket
        ssl.startHandshake()
        if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(host, ssl.session)) {
            runCatching { ssl.close() }
            throw SSLPeerUnverifiedException("The server's certificate isn't for $host.")
        }
        return ssl
    }
}

/** An open socket after a good handshake. */
internal class SocketWebSocket(
    private val socket: Socket,
    private val input: InputStream,
    private val output: OutputStream,
) : WebSocketConnection {

    private val writeLock = Any()
    private val random = SecureRandom()

    @Volatile
    private var closed = false

    override fun send(text: String): Boolean = write(WebSocketFrames.OP_TEXT, text.toByteArray(Charsets.UTF_8))

    override fun receive(): String? {
        val message = ByteArrayOutputStream()
        var inMessage = false
        while (!closed) {
            val frame = try {
                WebSocketFrames.read(input)
            } catch (e: IOException) {
                null
            }
            if (frame == null) {
                close()
                return null
            }
            when (frame.opcode) {
                WebSocketFrames.OP_PING -> write(WebSocketFrames.OP_PONG, frame.payload)
                WebSocketFrames.OP_PONG -> Unit
                WebSocketFrames.OP_CLOSE -> {
                    close()
                    return null
                }
                WebSocketFrames.OP_TEXT, WebSocketFrames.OP_BINARY -> {
                    message.reset()
                    message.write(frame.payload)
                    inMessage = true
                    if (frame.fin) return message.toString(Charsets.UTF_8.name())
                }
                WebSocketFrames.OP_CONTINUATION -> if (inMessage) {
                    message.write(frame.payload)
                    if (frame.fin) return message.toString(Charsets.UTF_8.name())
                }
            }
        }
        return null
    }

    override fun close() {
        if (closed) return
        closed = true
        // A TLS close writes to the network, which Android refuses on the main thread.
        Thread {
            runCatching { writeFrame(WebSocketFrames.OP_CLOSE, byteArrayOf(0x03, 0xE8.toByte())) } // 1000, normal
            runCatching { socket.close() }
        }.apply { isDaemon = true }.start()
    }

    private fun write(opcode: Int, payload: ByteArray): Boolean {
        if (closed) return false
        return try {
            writeFrame(opcode, payload)
            true
        } catch (e: IOException) {
            close()
            false
        }
    }

    private fun writeFrame(opcode: Int, payload: ByteArray) {
        val mask = ByteArray(4).also(random::nextBytes)
        val frame = WebSocketFrames.encode(opcode, payload, mask)
        synchronized(writeLock) {
            output.write(frame)
            output.flush()
        }
    }
}

/** The wire format: the upgrade request and frames (RFC 6455), as plain functions the tests can reach. */
internal object WebSocketFrames {
    const val OP_CONTINUATION = 0x0
    const val OP_TEXT = 0x1
    const val OP_BINARY = 0x2
    const val OP_CLOSE = 0x8
    const val OP_PING = 0x9
    const val OP_PONG = 0xA

    /** Realtime's frames are small; anything this big is a broken stream. */
    private const val MAX_FRAME = 16L * 1024 * 1024
    private const val MAX_HEAD = 16 * 1024
    private const val GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    class Frame(val fin: Boolean, val opcode: Int, val payload: ByteArray)

    /** Sends the upgrade request and checks the server's 101 answer. */
    fun handshake(input: InputStream, output: OutputStream, path: String, host: String, key: String = newKey()) {
        val request = buildString {
            append("GET ").append(path).append(" HTTP/1.1\r\n")
            append("Host: ").append(host).append("\r\n")
            append("Upgrade: websocket\r\n")
            append("Connection: Upgrade\r\n")
            append("Sec-WebSocket-Key: ").append(key).append("\r\n")
            append("Sec-WebSocket-Version: 13\r\n")
            append("User-Agent: Ketchup-Android\r\n")
            append("\r\n")
        }
        output.write(request.toByteArray(Charsets.US_ASCII))
        output.flush()

        val head = readHead(input)
        val lines = head.split("\r\n")
        val status = lines.first().split(' ').getOrNull(1)?.toIntOrNull()
        if (status != 101) throw IOException("Realtime refused the connection ($status).")
        val headers = lines.drop(1).mapNotNull { line ->
            val colon = line.indexOf(':')
            if (colon <= 0) null else line.substring(0, colon).trim().lowercase() to line.substring(colon + 1).trim()
        }.toMap()
        if (!headers["upgrade"].equals("websocket", ignoreCase = true)) throw IOException("Realtime didn't upgrade.")
        if (headers["sec-websocket-accept"] != accept(key)) throw IOException("Realtime's handshake didn't match.")
    }

    fun newKey(): String = Base64.getEncoder().encodeToString(ByteArray(16).also(SecureRandom()::nextBytes))

    /** What the server must answer for [key]. */
    fun accept(key: String): String =
        Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + GUID).toByteArray(Charsets.US_ASCII)))

    /** The status line and headers, up to the blank line, read a byte at a time so no frame bytes are taken. */
    private fun readHead(input: InputStream): String {
        val bytes = ByteArrayOutputStream()
        // The last four bytes read, newest in the low byte: "\r\n\r\n" ends the head.
        var last4 = 0
        while (true) {
            val b = input.read()
            if (b == -1) throw EOFException("Realtime closed during the handshake.")
            bytes.write(b)
            last4 = (last4 shl 8) or b
            if (last4 == END_OF_HEAD) {
                val all = bytes.toByteArray()
                return String(all, 0, all.size - 4, Charsets.ISO_8859_1)
            }
            if (bytes.size() > MAX_HEAD) throw IOException("Realtime's handshake was too long.")
        }
    }

    /** "\r\n\r\n" as four bytes in an Int. */
    private const val END_OF_HEAD = 0x0D0A0D0A

    /** One client frame: FIN set, masked with [mask] (clients must mask). */
    fun encode(opcode: Int, payload: ByteArray, mask: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(payload.size + 14)
        out.write(0x80 or opcode)
        val length = payload.size
        when {
            length < 126 -> out.write(0x80 or length)
            length <= 0xFFFF -> {
                out.write(0x80 or 126)
                out.write(length ushr 8 and 0xFF)
                out.write(length and 0xFF)
            }
            else -> {
                out.write(0x80 or 127)
                for (shift in 56 downTo 0 step 8) out.write((length.toLong() ushr shift and 0xFF).toInt())
            }
        }
        out.write(mask)
        for (i in payload.indices) out.write(payload[i].toInt() xor mask[i % 4].toInt() and 0xFF)
        return out.toByteArray()
    }

    /** The next frame, or null at the end of the stream. Unmasks a masked one (servers shouldn't mask, but may). */
    fun read(input: InputStream): Frame? {
        val b0 = input.read()
        if (b0 == -1) return null
        val b1 = readByte(input)
        val fin = b0 and 0x80 != 0
        val opcode = b0 and 0x0F
        val masked = b1 and 0x80 != 0
        var length = (b1 and 0x7F).toLong()
        if (length == 126L) {
            length = (readByte(input).toLong() shl 8) or readByte(input).toLong()
        } else if (length == 127L) {
            length = 0
            repeat(8) { length = (length shl 8) or readByte(input).toLong() }
        }
        if (length < 0 || length > MAX_FRAME) throw IOException("A Realtime frame was too big.")
        val mask = if (masked) ByteArray(4).also { readFully(input, it) } else null
        val payload = ByteArray(length.toInt()).also { readFully(input, it) }
        if (mask != null) for (i in payload.indices) payload[i] = (payload[i].toInt() xor mask[i % 4].toInt()).toByte()
        return Frame(fin, opcode, payload)
    }

    private fun readByte(input: InputStream): Int {
        val b = input.read()
        if (b == -1) throw EOFException("Realtime closed mid-frame.")
        return b
    }

    private fun readFully(input: InputStream, into: ByteArray) {
        var off = 0
        while (off < into.size) {
            val n = input.read(into, off, into.size - off)
            if (n == -1) throw EOFException("Realtime closed mid-frame.")
            off += n
        }
    }
}
