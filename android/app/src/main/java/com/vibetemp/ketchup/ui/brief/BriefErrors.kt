package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.data.ApiException
import kotlinx.serialization.SerializationException
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * A readable sentence for anything that goes wrong on the way to Muse Spark,
 * including the edge function not being deployed (404 from the gateway),
 * not configured (503) or the model failing (502). Pure Kotlin (JVM tests).
 * Port of iOS AI/AIPhase.swift `AIErrors`.
 */
object BriefErrors {
    fun message(error: Throwable): String = when (error) {
        is ApiException -> server(error.message.orEmpty())
        is SocketTimeoutException -> "Muse Spark took too long. Try again."
        is UnknownHostException, is ConnectException, is NoRouteToHostException ->
            "You're offline. Reconnect and try again."
        is SerializationException -> "Muse Spark sent back something unexpected. Try again."
        is IOException -> "Couldn't reach Muse Spark. Try again."
        else -> "Something went wrong. Try again."
    }

    private fun server(raw: String): String {
        val lower = raw.lowercase()
        return when {
            "function" in lower && "not found" in lower -> "Muse Spark isn't switched on yet. Try again soon."
            lower.startsWith("request failed (50") -> "Muse Spark is busy right now. Try again in a moment."
            raw.isBlank() -> "Couldn't reach Muse Spark. Try again."
            else -> raw
        }
    }
}
