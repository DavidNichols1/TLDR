package com.vibetemp.ketchup.ui.chat

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.brief.BriefActivity
import com.vibetemp.ketchup.ui.chats.AppModel
import com.vibetemp.ketchup.ui.chats.BAR_ROW
import com.vibetemp.ketchup.ui.chats.BackButton
import com.vibetemp.ketchup.ui.chats.ThreadSkeleton
import com.vibetemp.ketchup.ui.chats.findActivity
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** What a preview can ask of an opened chat. */
data class ChatStart(
    /** Jump to this message once the thread is in place, as if a brief asked. */
    val jumpTo: String? = null,
    /** Send this 1.2 s in, as if typed. */
    val send: String? = null,
    /** Open with the info sheet up. */
    val info: Boolean = false,
)

/**
 * One group chat (iOS `ChatView`): bubbles oldest first with sender names
 * in their colors, day lines and the "N new" line, older pages as you
 * scroll up, the pinned Catch me up bar, and the composer. New messages
 * come over Realtime, polling every 4 s while it isn't live. Catch me up
 * and Ask open the brief; when it comes back with a cited message, the
 * thread scrolls there (paging back if it must) and a mustard marker sweeps
 * behind it.
 *
 * The read cursor rules are ChatModel's; this screen only reports
 * scrolling and leaving.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(app: AppModel, chat: ChatSummary, onBack: () -> Unit, start: ChatStart = ChatStart()) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val scope = rememberCoroutineScope()
    val model = remember(chat.id) { app.chatModel(chat) }
    val state by model.state.collectAsState()
    val list = rememberLazyListState()
    var draft by rememberSaveable { mutableStateOf("") }
    var highlighted by remember { mutableStateOf<String?>(null) }
    // Messages to jump to (a brief's cited message); one at a time, in order.
    val jumps = remember { Channel<String>(Channel.CONFLATED) }
    // Saved, so a rotation keeps the thread where it was instead of placing it again.
    var positioned by rememberSaveable { mutableStateOf(false) }
    var userScrolled by rememberSaveable { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }
    var showInfo by rememberSaveable { mutableStateOf(start.info) }
    val tooFarBack = stringResource(R.string.chat_too_far_back)

    // Newest first, for a list laid out from the bottom (it stays put over the keyboard).
    val rows = remember(state.messages, state.firstUnreadId, state.unreadAtOpen) {
        threadRows(state.messages, state.firstUnreadId, state.unreadAtOpen).asReversed()
    }
    val atBottom by remember { derivedStateOf { !list.canScrollBackward } }

    // The brief: Catch me up and Ask both open it; a cited message comes back to jump to.
    val brief = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        // A catch-up moves the cursor on the server, so take it from there again.
        scope.launch { model.refreshCursor() }
        val id = result.data?.getStringExtra(BriefActivity.EXTRA_JUMP_TO_MESSAGE)
        if (result.resultCode == Activity.RESULT_OK && id != null) jumps.trySend(id)
    }
    fun openBrief() {
        brief.launch(BriefActivity.intent(context, BriefSource.Chat(chat.id, chat.name)))
    }
    fun openAsk() {
        brief.launch(BriefActivity.askIntent(context, BriefSource.Chat(chat.id, chat.name)))
    }

    // Loading, Realtime and the polling fallback, only while the app is on screen.
    LaunchedEffect(model) {
        val work: suspend () -> Unit = {
            coroutineScope {
                launch { model.open() }
                // While Realtime is down, poll every 4 s; when it comes back, one poll
                // fills the gap. Until the first page is in, keep trying either way.
                model.realtime.isLive.collectLatest { live ->
                    if (live) model.poll()
                    while (!model.realtime.isLive.value || !model.state.value.synced) {
                        delay(4_000)
                        model.poll()
                    }
                }
            }
        }
        try {
            if (activity != null) activity.repeatOnLifecycle(Lifecycle.State.STARTED) {
                try {
                    work()
                } finally {
                    model.realtime.stop()
                }
            } else {
                work()
            }
        } finally {
            model.realtime.stop()
        }
    }
    // Leaving for good (not a rotation): mark read if the bottom was seen.
    DisposableEffect(model) {
        onDispose {
            if (activity?.isChangingConfigurations != true) {
                model.close()
                app.forgetChat(chat.id)
            }
        }
    }
    LaunchedEffect(state.unreadCount) { if (state.unreadCount == 0) app.markReadLocally(chat.id) }
    LaunchedEffect(list) {
        list.interactionSource.interactions.collect { if (it is DragInteraction.Start) userScrolled = true }
    }

    // First stop, once the server's page is in: the "N new" line at the top if
    // anything's unread (so Catch me up still means something), else the bottom.
    LaunchedEffect(state.synced) {
        if (!state.synced || positioned) return@LaunchedEffect
        delay(60)
        if (!userScrolled) {
            val divider = rows.indexOfFirst { it is ThreadRow.Unread }
            if (divider >= 0) {
                list.scrollToItem(divider)
                // Offsets run up from the bottom here: lift the line until its top meets the viewport's.
                val info = list.layoutInfo
                val item = info.visibleItemsInfo.firstOrNull { it.index == divider }
                if (item != null) {
                    val gap = info.viewportEndOffset - (item.offset + item.size)
                    if (gap > 0) list.scrollBy(-gap.toFloat())
                }
            } else {
                list.scrollToItem(0)
            }
        }
        positioned = true
        // A short thread fits on screen: the bottom is already in view, so it counts as seen.
        if (!list.canScrollBackward && !userScrolled) model.sawBottom = true
        start.jumpTo?.let { jumps.trySend(it) }
    }
    LaunchedEffect(atBottom, positioned) {
        if (!atBottom || !positioned) return@LaunchedEffect
        if (userScrolled) model.reachedBottomByScrolling() else model.sawBottom = true
    }
    // A new bubble at the bottom: follow it if it's mine, or if you were at the
    // bottom (the row that was newest is still the lowest one you can see).
    val newest = state.messages.lastOrNull()
    var lastNewest by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(newest?.id) {
        val last = newest ?: return@LaunchedEffect
        val previous = lastNewest
        lastNewest = last.id
        val minePending = last.sender == model.myId && (last.pending || last.failed)
        if (!positioned && !minePending) return@LaunchedEffect
        val was = previous?.let { id -> rows.indexOfFirst { it.key == id } }?.coerceAtLeast(0) ?: 0
        if (last.sender == model.myId || list.firstVisibleItemIndex <= was) list.animateScrollToItem(0)
    }
    // Older pages as you scroll up.
    val nearTop by remember {
        derivedStateOf {
            val info = list.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()?.index ?: 0
            info.totalItemsCount > 0 && last >= info.totalItemsCount - 4
        }
    }
    LaunchedEffect(nearTop, state.messages.size, positioned, state.hasOlder) {
        if (nearTop && positioned && state.hasOlder) model.loadOlder()
    }
    // The jump back from a brief: page back until the message is here, bring
    // it to the middle, and sweep the marker behind it for a moment.
    LaunchedEffect(jumps) {
        for (id in jumps) {
            if (!model.ensureLoaded(id)) {
                toast = tooFarBack
                continue
            }
            val s = model.state.value
            val index = threadRows(s.messages, s.firstUnreadId, s.unreadAtOpen).asReversed().indexOfFirst { it.key == id }
            if (index < 0) continue
            // Wait for the list to have the rows a page back just added.
            withTimeoutOrNull(2_000) { snapshotFlow { list.layoutInfo.totalItemsCount }.first { it > index } }
            if (list.layoutInfo.visibleItemsInfo.none { it.index == index }) list.scrollToItem(index)
            // Offsets run up from the bottom here.
            val info = list.layoutInfo
            val item = info.visibleItemsInfo.firstOrNull { it.index == index }
            if (item != null) {
                val middle = (info.viewportStartOffset + info.viewportEndOffset) / 2f
                list.animateScrollBy(-(middle - (item.offset + item.size / 2f)))
            }
            delay(120)
            highlighted = id
            delay(1_800)
            if (highlighted == id) highlighted = null
        }
    }
    LaunchedEffect(toast) {
        if (toast != null) {
            delay(2_500)
            toast = null
        }
    }
    LaunchedEffect(start.send) {
        val text = start.send ?: return@LaunchedEffect
        delay(1_200)
        model.send(text)
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.ime)),
    ) {
        TopBar(
            chat = chat,
            people = if (state.members.isEmpty()) chat.memberCount else state.members.size,
            onBack = onBack,
            menu = menu,
            onMenu = { menu = it },
            onCatchUp = ::openBrief,
            onAsk = ::openAsk,
            onInfo = { showInfo = true },
        )
        if (state.loaded && state.messages.isNotEmpty()) {
            CatchUpBar(state.unreadCount, onCatchUp = ::openBrief, onAsk = ::openAsk)
        }
        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize(),
                reverseLayout = true,
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            ) {
                items(rows, key = { it.key }, contentType = { it::class }) { row ->
                    when (row) {
                        is ThreadRow.Day -> DayDivider(row.day)
                        is ThreadRow.Unread -> UnreadDivider(row.count)
                        is ThreadRow.Bubble -> BubbleRow(model, row, highlighted = highlighted == row.message.id)
                    }
                }
                if (state.hasOlder) {
                    item(key = "older") { OlderRow(loading = state.loadingOlder) { scope.launch { model.loadOlder() } } }
                }
            }
            ThreadNote(state, chat, onRetry = { scope.launch { model.open() } })
            Toast(toast, Modifier.align(Alignment.BottomCenter))
        }
        ChatInputBar(
            text = draft,
            onText = { draft = it },
            onSend = {
                val text = sendable(draft)
                if (text != null) {
                    draft = ""
                    model.send(text)
                }
            },
        )
    }

    if (showInfo) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showInfo = false },
            modifier = Modifier.statusBarsPadding(),
            sheetState = sheet,
            containerColor = colors.cream,
            contentColor = colors.ink,
            scrimColor = colors.ink.copy(alpha = 0.32f),
        ) {
            ChatInfoSheet(model, state, onDone = { showInfo = false }, onLeave = {
                showInfo = false
                app.leave(chat)
                onBack()
            })
        }
    }
}

/** The bar: back, the chat's name and how many people in the middle, and the … menu. */
@Composable
private fun TopBar(
    chat: ChatSummary,
    people: Int,
    onBack: () -> Unit,
    menu: Boolean,
    onMenu: (Boolean) -> Unit,
    onCatchUp: () -> Unit,
    onAsk: () -> Unit,
    onInfo: () -> Unit,
) {
    val colors = KetchupTheme.colors
    val peopleLine = pluralStringResource(R.plurals.chat_people, people, people)
    Row(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(BAR_ROW)
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BackButton(onBack)
        Column(
            Modifier
                .weight(1f)
                .semantics(mergeDescendants = true) { heading() },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(chat.name, style = KetchupTheme.type.serifHeadline, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(peopleLine, style = KetchupTheme.type.monoCaption2, color = colors.inkSoft, maxLines = 1)
        }
        Box {
            val label = stringResource(R.string.chat_options)
            Box(
                Modifier
                    .size(44.dp)
                    .pressable { onMenu(true) }
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) {
                ChatIcon(R.drawable.chat_ic_more, null, colors.ink, size = 24.dp)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { onMenu(false) }, containerColor = colors.card) {
                MenuItem(stringResource(R.string.chat_menu_catch_up), R.drawable.chat_ic_ask) {
                    onMenu(false)
                    onCatchUp()
                }
                MenuItem(stringResource(R.string.chat_menu_ask), R.drawable.chat_ic_ask) {
                    onMenu(false)
                    onAsk()
                }
                MenuItem(stringResource(R.string.chat_menu_info), R.drawable.chat_ic_people) {
                    onMenu(false)
                    onInfo()
                }
            }
        }
    }
}

@Composable
private fun MenuItem(text: String, icon: Int, onClick: () -> Unit) {
    val colors = KetchupTheme.colors
    DropdownMenuItem(
        text = { Text(text, style = KetchupTheme.type.body, color = colors.ink) },
        leadingIcon = { ChatIcon(icon, null, colors.ink, size = 20.dp) },
        onClick = onClick,
    )
}

/** A bubble with its sender's monogram by the last of each run (other people's only). */
@Composable
private fun BubbleRow(model: ChatModel, row: ThreadRow.Bubble, highlighted: Boolean) {
    val m = row.message
    val mine = m.sender == model.myId
    val name = model.name(m.sender)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = if (row.startsRun) 10.dp else 0.dp)
            .padding(vertical = 1.5.dp)
            // Under its neighbors, so the jump mark stays behind every bubble.
            .zIndex(if (highlighted) -1f else 0f),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (!mine) {
            if (row.endsRun) Monogram(name, size = 28.dp) else AvatarGap(28.dp)
        }
        ChatBubble(
            message = m,
            mine = mine,
            senderName = if (row.startsRun && !mine) name else null,
            senderColor = KetchupTheme.colors.person(name),
            startsRun = row.startsRun,
            endsRun = row.endsRun,
            highlighted = highlighted,
            onRetry = { model.retry(m.id) },
            modifier = Modifier.weight(1f),
        )
    }
}

/** The top of what's loaded: earlier messages load as you scroll up, or on a tap. */
@Composable
private fun OlderRow(loading: Boolean, onLoad: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
        if (loading) {
            Text(stringResource(R.string.chat_loading_earlier), style = KetchupTheme.type.monoCaption, color = KetchupTheme.colors.inkSoft)
        } else {
            Text(
                stringResource(R.string.chat_load_earlier),
                style = KetchupTheme.type.footnote.copy(fontWeight = FontWeight.SemiBold),
                color = KetchupTheme.colors.ketchupText,
                modifier = Modifier.pressable(onClick = onLoad).padding(8.dp),
            )
        }
    }
}

/** What the thread says when there's nothing to show yet: a skeleton, a failed load, or an empty chat. */
@Composable
private fun ThreadNote(state: ChatState, chat: ChatSummary, onRetry: () -> Unit) {
    val colors = KetchupTheme.colors
    val error = state.loadError
    when {
        !state.loaded && error != null -> Note(stringResource(R.string.chat_error_title), error) {
            CapsuleButton(stringResource(R.string.chat_try_again), onClick = onRetry, fill = ButtonFill.Outline, compact = true)
        }
        !state.loaded -> ThreadSkeleton(stringResource(R.string.chat_loading), Modifier.background(colors.cream))
        state.messages.isEmpty() -> {
            val line = stringResource(R.string.chat_empty_body, chat.inviteCode)
            val at = line.indexOf(chat.inviteCode)
            val text = buildAnnotatedString {
                if (at < 0) {
                    append(line)
                } else {
                    append(line.substring(0, at))
                    withStyle(SpanStyle(fontFamily = KetchupTheme.type.monoBody.fontFamily, fontWeight = FontWeight.SemiBold, color = colors.ink)) {
                        append(chat.inviteCode)
                    }
                    append(line.substring(at + chat.inviteCode.length))
                }
            }
            Note(stringResource(R.string.chat_empty_title), null, annotated = text) {}
        }
    }
}

@Composable
private fun Note(
    title: String,
    message: String?,
    annotated: androidx.compose.ui.text.AnnotatedString? = null,
    actions: @Composable () -> Unit,
) {
    Box(Modifier.fillMaxSize().background(KetchupTheme.colors.cream), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                title,
                style = KetchupTheme.type.serifTitle3,
                color = KetchupTheme.colors.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() },
            )
            if (annotated != null) {
                Text(annotated, style = KetchupTheme.type.body, color = KetchupTheme.colors.inkSoft, textAlign = TextAlign.Center)
            } else if (message != null) {
                Text(message, style = KetchupTheme.type.body, color = KetchupTheme.colors.inkSoft, textAlign = TextAlign.Center)
            }
            Box(Modifier.padding(top = 4.dp)) { actions() }
        }
    }
}

/** A short note over the composer ("That message is too far back to show"). */
@Composable
private fun Toast(text: String?, modifier: Modifier = Modifier) {
    // Keeps its words while it fades out.
    var last by remember { mutableStateOf("") }
    if (text != null) last = text
    AnimatedVisibility(
        visible = text != null,
        modifier = modifier.padding(bottom = 16.dp),
        enter = fadeIn() + slideInVertically { it / 2 },
        exit = fadeOut() + slideOutVertically { it / 2 },
    ) {
        Text(
            last,
            style = KetchupTheme.type.footnote.copy(fontWeight = FontWeight.SemiBold),
            color = KetchupTheme.colors.onInk,
            modifier = Modifier
                .background(KetchupTheme.colors.ink, CircleShape)
                .padding(horizontal = 16.dp, vertical = 10.dp),
        )
    }
}
