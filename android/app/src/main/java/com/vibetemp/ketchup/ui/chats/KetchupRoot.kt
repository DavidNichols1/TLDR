package com.vibetemp.ketchup.ui.chats

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.auth.NameScreen
import com.vibetemp.ketchup.ui.auth.SignInScreen
import com.vibetemp.ketchup.ui.auth.TermsScreen
import com.vibetemp.ketchup.ui.chat.ChatScreen
import com.vibetemp.ketchup.ui.chat.ChatStart
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion

/**
 * The chat slice's nav graph (iOS `RootView`): sign-in until there's a
 * session, the terms screen while this version of the terms isn't agreed to
 * (data/TermsGate.kt), the name step once after sign-up, then the home.
 */
@Composable
fun KetchupRoot(app: AppModel) {
    LaunchedEffect(app.myId) { app.loadMe() }
    LaunchedEffect(app.myId) { app.checkTerms() }
    val screen = when {
        !app.isSignedIn -> "signin"
        app.termsNeeded -> "terms"
        app.needsName -> "name"
        else -> "home"
    }
    AnimatedContent(
        targetState = screen,
        transitionSpec = { fadeIn(Motion.settle()) togetherWith fadeOut(Motion.fade()) },
        label = "root",
    ) { which ->
        when (which) {
            "signin" -> SignInScreen(app.api, onSignedIn = app::signedIn)
            "terms" -> TermsScreen(app)
            "name" -> NameScreen(app)
            else -> Home(app)
        }
    }
}

/** Where the home opens: previews start on a page, a sheet, or a pushed screen. */
data class HomeStart(
    val page: HomePage? = null,
    val remembers: Boolean = true,
    val sheet: InboxSheet? = null,
    /** Routes pushed over the pager: "chat:<id>", "settings", "name". */
    val stack: List<String> = emptyList(),
    val chat: ChatStart = ChatStart(),
)

/**
 * The signed-in home: the pager, with a chat, Settings or Change your name
 * pushed over it. Back pops (the system's back gesture too). Each route's
 * saved state (the inbox's scroll, the pager's page) comes back with it.
 */
@Composable
fun Home(app: AppModel, start: HomeStart = HomeStart()) {
    val stack = rememberSaveable(saver = listSaver(save = { it.toList() }, restore = { it.toMutableStateList() })) {
        start.stack.toMutableStateList()
    }
    val holder = rememberSaveableStateHolder()
    val reduceMotion = KetchupTheme.reduceMotion
    fun pop() {
        if (stack.isEmpty()) return
        // Forget the screen's saved state too, so opening it again starts fresh.
        holder.removeState(stack.removeAt(stack.lastIndex))
    }
    // A chat restored after the process died needs the inbox to find it.
    LaunchedEffect(Unit) { if (!app.chatsLoaded) app.refreshChats() }
    BackHandler(enabled = stack.isNotEmpty()) { pop() }

    AnimatedContent(
        targetState = (stack.lastOrNull() ?: PAGER) to stack.size,
        transitionSpec = {
            val forward = targetState.second > initialState.second
            if (reduceMotion) {
                fadeIn(Motion.fade()) togetherWith fadeOut(Motion.fade())
            } else if (forward) {
                slideInHorizontally(Motion.settle()) { it } togetherWith slideOutHorizontally(Motion.settle()) { -it / 4 }
            } else {
                // Back: the screen leaving slides off over the one coming back, not under it.
                (slideInHorizontally(Motion.settle()) { -it / 4 } togetherWith slideOutHorizontally(Motion.settle()) { it })
                    .apply { targetContentZIndex = -1f }
            }
        },
        contentKey = { it.first },
        label = "home",
    ) { (route, _) ->
        holder.SaveableStateProvider(route) {
            when {
                route == PAGER -> HomePager(
                    app,
                    onOpenChat = { stack.add("chat:${it.id}") },
                    onOpenSettings = { stack.add(SETTINGS) },
                    start = start.page,
                    remembers = start.remembers,
                    inboxSheet = start.sheet,
                )
                route.startsWith("chat:") -> {
                    // The inbox's row, or the last one seen: a chat you just left slides out as itself.
                    val current = app.chat(route.removePrefix("chat:"))
                    val last = remember(route) { mutableStateOf(current) }
                    if (current != null) last.value = current
                    val chat = current ?: last.value
                    if (chat != null) ChatScreen(app, chat, onBack = ::pop, start = start.chat) else NotFound()
                }
                route == SETTINGS -> SettingsScreen(app, onBack = ::pop, onEditName = { stack.add(EDIT_NAME) })
                route == EDIT_NAME -> EditNameScreen(app, onDone = ::pop)
                else -> NotFound()
            }
        }
    }
}

/** A chat that isn't in the inbox (left, or not loaded yet). */
@Composable
private fun NotFound() {
    Box(Modifier.fillMaxSize().background(KetchupTheme.colors.cream), contentAlignment = Alignment.Center) {
        Text(stringResource(R.string.chat_not_found), style = KetchupTheme.type.serifTitle3, color = KetchupTheme.colors.inkSoft)
    }
}

private const val PAGER = "pager"
private const val SETTINGS = "settings"
private const val EDIT_NAME = "name"
