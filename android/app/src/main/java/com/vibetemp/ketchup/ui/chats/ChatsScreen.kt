package com.vibetemp.ketchup.ui.chats

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.chat.ChatModel
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Which of the inbox's sheets is up. */
enum class InboxSheet { NewChat, Join }

/** The height of a top bar's row of buttons, under the status bar. The pager's switcher sits in it. */
val BAR_ROW = 52.dp

/**
 * The inbox (iOS `ChatsListView`), the home pager's first page: my_chats
 * newest first with unread badges and previews, paper skeletons on the
 * first load, an empty state, pull to refresh, New chat and Join with code
 * from the +, and Settings from your monogram at the top left. The middle
 * of its top bar stays free for the pager's switcher.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatsScreen(
    app: AppModel,
    onOpenChat: (ChatSummary) -> Unit,
    onOpenSettings: () -> Unit,
    startSheet: InboxSheet? = null,
) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sheet by rememberSaveable { mutableStateOf(startSheet) }
    var newName by rememberSaveable { mutableStateOf("") }
    var joinCode by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }

    // Fresh while it's on screen (badges, previews), every 15 s.
    val activity = remember(context) { context.findActivity() }
    LaunchedEffect(app, activity) {
        val loop: suspend () -> Unit = {
            while (true) {
                app.refreshChats()
                delay(15_000)
            }
        }
        if (activity != null) activity.repeatOnLifecycle(Lifecycle.State.STARTED) { loop() } else loop()
    }

    fun open(id: String) {
        app.chat(id)?.let(onOpenChat)
    }

    fun create() {
        if (busy) return // a second tap while it's still going
        val name = newName.trim().take(50)
        newName = ""
        sheet = null
        if (name.isEmpty()) return
        busy = true
        scope.launch {
            try {
                val id = app.createChat(name)
                app.refreshChats()
                open(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = ChatModel.readable(e)
            } finally {
                busy = false
            }
        }
    }

    fun join() {
        if (busy) return
        val code = InviteCode.clean(joinCode)
        joinCode = ""
        sheet = null
        if (code.length != InviteCode.LENGTH) {
            error = context.getString(R.string.chats_bad_code)
            return
        }
        busy = true
        scope.launch {
            try {
                val id = app.joinChat(code)
                if (id == null) {
                    error = context.getString(R.string.chats_no_such_code, code)
                } else {
                    app.refreshChats()
                    open(id)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = ChatModel.readable(e)
            } finally {
                busy = false
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream),
    ) {
        // The top bar: your monogram (Settings) and +; the middle is the switcher's.
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(BAR_ROW)
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val me = app.me
            val settingsLabel = if (me != null) stringResource(R.string.chats_settings_named, me.displayName) else stringResource(R.string.chats_settings)
            Box(
                Modifier
                    .size(44.dp)
                    .pressable(onClick = onOpenSettings)
                    .semantics { contentDescription = settingsLabel },
                contentAlignment = Alignment.Center,
            ) {
                Monogram(me?.displayName ?: "?", size = 30.dp)
            }
            Spacer(Modifier.weight(1f))
            Box {
                val plusLabel = stringResource(R.string.chats_new_or_join)
                Box(
                    Modifier
                        .size(44.dp)
                        .pressable(enabled = !busy) { menu = true }
                        .semantics { contentDescription = plusLabel },
                    contentAlignment = Alignment.Center,
                ) {
                    if (busy) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = colors.ink, strokeWidth = 2.dp)
                    } else {
                        ChatIcon(R.drawable.chat_ic_plus, null, colors.ink, size = 26.dp)
                    }
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = colors.card) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.chats_menu_new), style = KetchupTheme.type.body, color = colors.ink) },
                        leadingIcon = { ChatIcon(R.drawable.chat_ic_pencil, null, colors.ink, size = 20.dp) },
                        onClick = {
                            menu = false
                            sheet = InboxSheet.NewChat
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.chats_menu_join), style = KetchupTheme.type.body, color = colors.ink) },
                        leadingIcon = { ChatIcon(R.drawable.chat_ic_people, null, colors.ink, size = 20.dp) },
                        onClick = {
                            menu = false
                            sheet = InboxSheet.Join
                        },
                    )
                }
            }
        }

        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                refreshing = true
                scope.launch {
                    app.refreshChats()
                    refreshing = false
                }
            },
            modifier = Modifier.weight(1f),
        ) {
            val waiting = !app.chatsLoaded && app.chats.isEmpty() && app.notice == null
            LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
                item(key = "header") { InboxHeader(app) }
                if (waiting) item(key = "skeleton") { InboxSkeleton(stringResource(R.string.chats_loading)) }
                itemsIndexed(app.chats, key = { _, chat -> chat.id }) { index, chat ->
                    Column(Modifier.animateItem()) {
                        ChatListRow(chat, onOpen = { onOpenChat(chat) })
                        if (index < app.chats.size - 1) RowHairline()
                    }
                }
                item(key = "bottom") { Spacer(Modifier.navigationBarsPadding()) }
            }
            EmptyOrError(
                app,
                onRetry = { scope.launch { app.refreshChats() } },
                onStart = { sheet = InboxSheet.NewChat },
                onJoin = { sheet = InboxSheet.Join },
            )
        }
    }

    sheet?.let { which ->
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { sheet = null },
            sheetState = state,
            containerColor = colors.cream,
            contentColor = colors.ink,
            scrimColor = colors.ink.copy(alpha = 0.32f),
        ) {
            when (which) {
                InboxSheet.NewChat -> NewChatSheet(newName, { newName = it }, onCreate = ::create, onCancel = {
                    newName = ""
                    sheet = null
                })
                InboxSheet.Join -> JoinChatSheet(joinCode, { joinCode = it }, onJoin = ::join, onCancel = {
                    joinCode = ""
                    sheet = null
                })
            }
        }
    }

    val shown = error ?: app.problem
    if (shown != null) {
        AlertDialog(
            onDismissRequest = {
                error = null
                app.problem = null
            },
            confirmButton = {
                TextButton(onClick = {
                    error = null
                    app.problem = null
                }) { Text(stringResource(R.string.chats_ok), color = colors.ketchupText) }
            },
            title = { Text(stringResource(R.string.chats_problem_title), style = KetchupTheme.type.serifTitle3, color = colors.ink) },
            text = { Text(shown, style = KetchupTheme.type.body, color = colors.inkSoft) },
            containerColor = colors.card,
        )
    }
}

/** "Chats" in serif, with how much is waiting over it. */
@Composable
private fun InboxHeader(app: AppModel) {
    val unread = app.chats.sumOf { it.unreadCount }
    val me = app.me
    val summary = when {
        app.chats.isEmpty() -> if (me != null) stringResource(R.string.chats_hi, me.displayName) else stringResource(R.string.chats_inbox)
        unread == 0 -> stringResource(R.string.chats_all_caught_up)
        else -> pluralStringResource(R.plurals.chats_new_messages, unread, unread)
    }
    Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Kicker(summary)
        Text(
            stringResource(R.string.chats_title),
            style = KetchupTheme.type.serifLargeTitle,
            color = KetchupTheme.colors.ink,
            modifier = Modifier.semantics { heading() },
        )
    }
}

/** The empty inbox, and the inbox that couldn't load: a big drop, a serif line, a sentence, what to do. */
@Composable
private fun EmptyOrError(app: AppModel, onRetry: () -> Unit, onStart: () -> Unit, onJoin: () -> Unit) {
    val notice = app.notice
    when {
        !app.chatsLoaded && app.chats.isEmpty() && notice != null -> EmptyCounter(
            title = stringResource(R.string.chats_error_title),
            message = notice,
        ) {
            CapsuleButton(stringResource(R.string.chats_try_again), onClick = onRetry, fill = ButtonFill.Outline, compact = true)
        }
        app.chatsLoaded && app.chats.isEmpty() -> EmptyCounter(
            title = stringResource(R.string.chats_empty_title),
            message = stringResource(R.string.chats_empty_body),
        ) {
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                CapsuleButton(stringResource(R.string.chats_start), onClick = onStart)
                CapsuleButton(stringResource(R.string.chats_join), onClick = onJoin, fill = ButtonFill.Outline)
            }
        }
    }
}

@Composable
private fun EmptyCounter(title: String, message: String, actions: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .widthIn(max = 440.dp)
                .padding(horizontal = 36.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            KetchupDrop(size = 84.dp, modifier = Modifier
                .padding(bottom = 6.dp)
                .rotate(-8f))
            Text(
                title,
                style = KetchupTheme.type.serifTitle2,
                color = KetchupTheme.colors.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() },
            )
            Text(message, style = KetchupTheme.type.body, color = KetchupTheme.colors.inkSoft, textAlign = TextAlign.Center)
            actions()
        }
    }
}

/** The activity behind a composable's context, for its lifecycle. */
fun Context.findActivity(): ComponentActivity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is ComponentActivity) return current
        current = current.baseContext
    }
    return null
}
