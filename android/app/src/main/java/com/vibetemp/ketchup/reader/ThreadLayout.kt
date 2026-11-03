package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextSource

/**
 * Spots an open DM thread by its shape: a message list filling the middle
 * of the screen, with the composer under it. Looks only at structure, view
 * ids and the composer's hint, so it can run without the person's tap.
 *
 * - Instagram's view ids are obfuscated and change between releases, so it
 *   goes by shape and the composer's hint ("Message...") alone. The hint
 *   also keeps a post's comment sheet ("Add a comment...") from counting.
 * - Snapchat keeps a few ids readable (a dump of the real app, Nov 3,
 *   2026): the composer is `chat_input_text_field` and the list
 *   `chat_message_list`. Those count first; its hint ("Send a chat") and
 *   the shape rules are the fallback.
 */
object ThreadLayout {

    /** An open thread: where its list and composer are, in screen pixels. */
    data class Found(val list: Bounds, val composer: Bounds)

    private val LIST_CLASS = Regex("(RecyclerView|ListView|ScrollView|GridView|LazyList|LazyColumn)")
    private val COMPOSER_HINT = mapOf(
        TextSource.INSTAGRAM to Regex("^message\\b", RegexOption.IGNORE_CASE),
        TextSource.SNAPCHAT to Regex("^(send a chat|send a message|chat)\\b", RegexOption.IGNORE_CASE),
    )

    /** View ids (the part after ":id/") that name the composer and the list, per app. */
    private val COMPOSER_ID = mapOf(TextSource.SNAPCHAT to "chat_input_text_field")
    private val LIST_ID = mapOf(TextSource.SNAPCHAT to "chat_message_list")

    /** The thread on screen, or null when [root] isn't one. */
    fun detect(root: ReaderNode, source: TextSource): Found? {
        val composer = findComposer(root, source) ?: return null
        val list = findList(root, composer.bounds, source) ?: return null
        return Found(list.bounds, composer.bounds)
    }

    /**
     * The message composer: an editable field in the lower half whose view
     * id is the app's composer (Snapchat), or whose hint reads like one.
     */
    fun findComposer(root: ReaderNode, source: TextSource): ReaderNode? {
        val pattern = COMPOSER_HINT.getValue(source)
        val id = COMPOSER_ID[source]
        var byHint: ReaderNode? = null
        var byId: ReaderNode? = null
        for (node in lowerEditables(root)) {
            if (byId == null && id != null && idName(node) == id) byId = node
            val says = listOfNotNull(node.hint, node.contentDescription, node.text).map(String::trim)
            if (byHint == null && says.any(pattern::containsMatchIn)) byHint = node
        }
        return byId ?: byHint
    }

    /**
     * The thread's message list: the app's list by view id (Snapchat), else
     * the biggest visible scrolling (or list-like) node above the composer
     * that fills most of the width and at least a quarter of the height. A
     * short thread's list may not scroll, so a list's class name counts too.
     */
    fun findList(root: ReaderNode, composer: Bounds?, source: TextSource? = null): ReaderNode? {
        val screen = root.bounds
        val id = source?.let(LIST_ID::get)
        var byId: ReaderNode? = null
        var best: ReaderNode? = null
        var bestArea = 0L
        root.walkTree { node, _ ->
            val b = node.bounds
            if (!node.isVisibleToUser || b.isEmpty) return@walkTree
            if (byId == null && id != null && idName(node) == id && b.height >= screen.height * 0.25) byId = node
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
        return byId ?: best
    }

    /**
     * Why there's no thread on [root], for the debug log: which step failed,
     * and the lower editable fields' view ids and hint lengths. Never text.
     */
    fun diagnose(root: ReaderNode, source: TextSource): String {
        val fields = lowerEditables(root).joinToString(", ") { "${idName(it) ?: "no id"} h=${it.hint?.length ?: 0}" }
            .ifEmpty { "no editable field in the lower half" }
        val composer = findComposer(root, source) ?: return "no composer ($fields)"
        if (findList(root, composer.bounds, source) != null) return "found"
        val lists = mutableListOf<String>()
        root.walkTree { node, _ ->
            if (node.isVisibleToUser && !node.bounds.isEmpty && (node.isScrollable || node.className?.let(LIST_CLASS::containsMatchIn) == true)) {
                lists += "${idName(node) ?: node.className?.substringAfterLast('.') ?: "?"} ${node.bounds}"
            }
        }
        return "no list (composer ${idName(composer) ?: "no id"}; scrollers: ${lists.joinToString().ifEmpty { "none" }})"
    }

    /** Visible editable fields in the lower part of the screen, where a composer sits. */
    private fun lowerEditables(root: ReaderNode): List<ReaderNode> {
        val screen = root.bounds
        val out = mutableListOf<ReaderNode>()
        root.walkTree { node, _ ->
            if (!node.isEditable || !node.isVisibleToUser || node.bounds.isEmpty) return@walkTree
            if (node.bounds.top < screen.top + screen.height * 0.45) return@walkTree
            out += node
        }
        return out
    }

    /** "chat_input_text_field" for "com.snapchat.android:id/chat_input_text_field". */
    internal fun idName(node: ReaderNode): String? = node.viewId?.substringAfter(":id/")?.ifEmpty { null }
}
