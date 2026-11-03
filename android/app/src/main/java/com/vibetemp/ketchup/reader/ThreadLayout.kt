package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextSource

/**
 * Spots an open DM thread by its shape, never by view ids (Instagram's are
 * obfuscated and change between releases): a message list filling the
 * middle of the screen, with the composer under it ("Message..." on
 * Instagram, "Send a chat" on Snapchat). Looks only at structure and the
 * composer's hint, so it can run without the person's tap.
 */
object ThreadLayout {

    /** An open thread: where its list and composer are, in screen pixels. */
    data class Found(val list: Bounds, val composer: Bounds)

    private val LIST_CLASS = Regex("(RecyclerView|ListView|ScrollView|GridView|LazyList|LazyColumn)")
    private val COMPOSER_HINT = mapOf(
        TextSource.INSTAGRAM to Regex("^message\\b", RegexOption.IGNORE_CASE),
        TextSource.SNAPCHAT to Regex("^(send a chat|send a message|chat)\\b", RegexOption.IGNORE_CASE),
    )

    /** The thread on screen, or null when [root] isn't one. */
    fun detect(root: ReaderNode, source: TextSource): Found? {
        val composer = findComposer(root, source) ?: return null
        val list = findList(root, composer.bounds) ?: return null
        return Found(list.bounds, composer.bounds)
    }

    /** The message composer: an editable field in the lower half whose hint reads like one. */
    fun findComposer(root: ReaderNode, source: TextSource): ReaderNode? {
        val pattern = COMPOSER_HINT.getValue(source)
        val screen = root.bounds
        var found: ReaderNode? = null
        root.walkTree { node, _ ->
            if (found != null || !node.isEditable || !node.isVisibleToUser || node.bounds.isEmpty) return@walkTree
            if (node.bounds.top < screen.top + screen.height * 0.45) return@walkTree
            val says = listOfNotNull(node.hint, node.contentDescription, node.text).map(String::trim)
            if (says.any(pattern::containsMatchIn)) found = node
        }
        return found
    }

    /**
     * The thread's message list: the biggest visible scrolling (or
     * list-like) node above the composer that fills most of the width and
     * at least a quarter of the height. A short thread's list may not
     * scroll, so a list's class name counts too.
     */
    fun findList(root: ReaderNode, composer: Bounds?): ReaderNode? {
        val screen = root.bounds
        var best: ReaderNode? = null
        var bestArea = 0L
        root.walkTree { node, _ ->
            val b = node.bounds
            if (!node.isVisibleToUser || b.isEmpty) return@walkTree
            if (!node.isScrollable && node.className?.let(LIST_CLASS::containsMatchIn) != true) return@walkTree
            if (b.width < screen.width * 0.6 || b.height < screen.height * 0.25) return@walkTree
            // Some apps draw the composer over the list's bottom edge, so only its middle must be above it.
            if (composer != null && (b.top + b.bottom) / 2 >= composer.top) return@walkTree
            val area = b.width.toLong() * b.height
            if (area > bestArea) {
                best = node
                bestArea = area
            }
        }
        return best
    }
}
