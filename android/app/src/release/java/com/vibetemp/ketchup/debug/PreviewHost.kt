package com.vibetemp.ketchup.debug

import androidx.compose.runtime.Composable

/** Release builds have no fixture screens: `--es screen` is ignored (the debug twin is in src/debug). */
object PreviewHost {
    const val EXTRA_SCREEN = "screen"
    const val AVAILABLE = false

    @Suppress("UNUSED_PARAMETER")
    @Composable
    fun Screen(name: String) = Unit
}
