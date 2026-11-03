package com.vibetemp.ketchup.ui.chats

import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.reader.ReaderPage
import com.vibetemp.ketchup.ui.chat.drawMarker
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt

/** A page of the signed-in home, left to right. [id] is what the app remembers. */
enum class HomePage(val id: String, val source: TextSource?) {
    CHATS("chats", null),
    INSTAGRAM("instagram", TextSource.INSTAGRAM),
    SNAPCHAT("snapchat", TextSource.SNAPCHAT),
}

/**
 * The signed-in home (iOS `HomePager`): Chats, Instagram and Snapchat side
 * by side. Swipe between them, or tap a name in the switcher at the top,
 * where a mustard mark slides along under the page you're on. Chats is the
 * first page, and the app comes back to the page you were on last. The
 * Instagram and Snapchat pages are the reader slice's [ReaderPage]; each is
 * built the first time you head its way, then kept.
 */
@Composable
fun HomePager(
    app: AppModel,
    onOpenChat: (ChatSummary) -> Unit,
    onOpenSettings: () -> Unit,
    start: HomePage? = null,
    remembers: Boolean = true,
    inboxSheet: InboxSheet? = null,
) {
    val pages = HomePage.entries
    val first = remember { start ?: pages.firstOrNull { it.id == app.homePage } ?: HomePage.CHATS }
    val pager = rememberPagerState(initialPage = first.ordinal) { pages.size }
    var built by remember { mutableStateOf(setOf(HomePage.CHATS, first)) }
    val scope = rememberCoroutineScope()
    val reduceMotion = KetchupTheme.reduceMotion

    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { if (remembers) app.homePage = pages[it].id }
    }
    // Build the page a swipe is heading for, so it's there as it slides in.
    LaunchedEffect(pager) {
        snapshotFlow { pager.currentPage + pager.currentPageOffsetFraction }.collect { position ->
            val low = floor(position).toInt().coerceIn(0, pages.size - 1)
            val high = (low + 1).coerceAtMost(pages.size - 1)
            val near = setOf(pages[low], if (position - low > 0.01f) pages[high] else pages[low])
            if (!built.containsAll(near)) built = built + near
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(KetchupTheme.colors.cream),
    ) {
        HorizontalPager(
            state = pager,
            modifier = Modifier.fillMaxSize(),
            beyondViewportPageCount = pages.size - 1,
            key = { pages[it].id },
        ) { index ->
            val page = pages[index]
            val source = page.source
            if (source == null) {
                ChatsScreen(app, onOpenChat, onOpenSettings, startSheet = inboxSheet)
            } else {
                // The other pages start under the switcher's row, on cream until they're built.
                Column(Modifier.fillMaxSize()) {
                    Spacer(
                        Modifier
                            .statusBarsPadding()
                            .height(BAR_ROW),
                    )
                    if (page in built) ReaderPage(source, Modifier.weight(1f)) else Spacer(Modifier.weight(1f))
                }
            }
        }
        HomeSwitcher(
            position = pager.currentPage + pager.currentPageOffsetFraction,
            titles = pages.map { it.source?.appName ?: stringResource(R.string.home_page_chats) },
            select = { target ->
                built = built + pages[target]
                scope.launch {
                    if (reduceMotion) pager.scrollToPage(target) else pager.animateScrollToPage(target, animationSpec = tween(450, easing = Motion.sweepEasing))
                }
            },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .height(BAR_ROW)
                .padding(horizontal = 60.dp),
        )
    }
}

/**
 * The pages' names across the top bar: serif, ink for the page you're on
 * and inkSoft for the rest, with a mustard marker stroke under the current
 * one that slides along as the pages scroll. Like a bar title it keeps its
 * size past the default text size.
 */
@Composable
private fun HomeSwitcher(position: Float, titles: List<String>, select: (Int) -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val density = LocalDensity.current
    val labels = remember { mutableStateMapOf<Int, Rect>() }
    val boxes = remember { mutableStateMapOf<Int, Rect>() }
    val current = position.roundToInt().coerceIn(0, titles.size - 1)
    // Bar titles keep their size; past the default text size they don't grow.
    val fontSize = (16f / maxOf(density.fontScale, 1f)).sp
    Row(
        modifier
            .background(colors.cream)
            .drawBehind {
                val clamped = position.coerceIn(0f, (titles.size - 1).toFloat())
                val lower = floor(clamped).toInt()
                val upper = min(lower + 1, titles.size - 1)
                val from = label(lower, boxes, labels) ?: return@drawBehind
                val to = label(upper, boxes, labels) ?: return@drawBehind
                val t = clamped - lower
                val x = from.left + (to.left - from.left) * t
                val width = from.width + (to.width - from.width) * t
                val reach = 3.dp.toPx()
                drawMarker(
                    colors.mustard,
                    topLeft = Offset(x - reach, from.bottom - 1.dp.toPx()),
                    size = Size(width + reach * 2, 7.dp.toPx()),
                )
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        titles.forEachIndexed { index, title ->
            Box(
                Modifier
                    .fillMaxHeight()
                    .onPlaced { boxes[index] = it.boundsInParent() }
                    .clickable(role = Role.Tab) { select(index) }
                    .semantics { selected = index == current }
                    .padding(horizontal = 7.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    title,
                    style = KetchupTheme.type.serifHeadline.copy(fontSize = fontSize, lineHeight = fontSize * 1.3f),
                    color = if (index == current) colors.ink else colors.inkSoft,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Visible,
                    modifier = Modifier.onPlaced { labels[index] = it.boundsInParent() },
                )
            }
        }
    }
}

/** A label's text bounds in the switcher row. */
private fun label(index: Int, boxes: Map<Int, Rect>, labels: Map<Int, Rect>): Rect? {
    val box = boxes[index] ?: return null
    val text = labels[index] ?: return null
    return text.translate(box.topLeft)
}
