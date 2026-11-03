package com.vibetemp.ketchup

import java.io.File

/** Reads repo files from a JVM test, whether Gradle runs it from `android/app` or `android/`. */
object Fixtures {
    /** A debug fixture in src/debug/assets/fixtures/. */
    fun asset(name: String): String = read("src/debug/assets/fixtures/$name")

    /** A file from the repo root (the iOS fixtures). */
    fun repo(path: String): String = read("../../$path")

    private fun read(relative: String): String {
        val candidates = listOf(File(relative), File("app", relative), File(relative.removePrefix("../")))
        val file = candidates.firstOrNull(File::isFile)
            ?: error("No $relative from ${File(".").absolutePath}")
        return file.readText()
    }
}
