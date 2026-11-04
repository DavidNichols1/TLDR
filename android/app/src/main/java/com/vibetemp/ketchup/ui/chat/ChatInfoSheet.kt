package com.vibetemp.ketchup.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.auth.TextAction
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * Members, the invite code (share or copy), and Leave chat (iOS
 * `ChatInfoSheet`), asked once more before it goes.
 */
@Composable
fun ChatInfoSheet(model: ChatModel, state: ChatState, onDone: () -> Unit, onLeave: () -> Unit) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val chat = model.chat
    val code = chat.inviteCode
    val people = if (state.members.isEmpty()) chat.memberCount else state.members.size
    var copied by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    val shareText = stringResource(R.string.info_share_text, chat.name, code)
    val shareTitle = stringResource(R.string.info_share)

    LaunchedEffect(model) { model.loadMembers() }

    Column(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Box(Modifier.fillMaxWidth()) {
            Text(
                chat.name,
                style = KetchupTheme.type.serifHeadline,
                color = colors.ink,
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.Center)
                    .semantics { heading() },
            )
            TextAction(stringResource(R.string.info_done), colors.ketchupText, enabled = true, onClick = onDone, modifier = Modifier.align(Alignment.CenterEnd))
        }

        // The code on paper, people counted on the stub, then Share (the ketchup one) and Copy.
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.paperCard(padding = 0.dp).height(IntrinsicSize.Min)) {
                Column(
                    Modifier
                        .weight(0.74f)
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Kicker(stringResource(R.string.info_invite_code))
                    val spoken = code.toList().joinToString(" ")
                    Text(
                        code,
                        style = KetchupTheme.type.monoBody.copy(fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 5.sp),
                        color = colors.ink,
                        maxLines = 1,
                        modifier = Modifier.semantics { contentDescription = spoken },
                    )
                }
                Box(Modifier.width(1.dp).fillMaxHeight().background(colors.rule))
                Column(
                    Modifier
                        .weight(0.26f)
                        .fillMaxHeight()
                        .padding(vertical = 18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        people.toString(),
                        style = KetchupTheme.type.monoBody.copy(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
                        color = colors.ink,
                    )
                    Kicker(stringResource(if (people == 1) R.string.info_person else R.string.info_people))
                }
            }
            Text(stringResource(R.string.info_anyone), style = KetchupTheme.type.footnote, color = colors.inkSoft)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CapsuleButton(
                    shareTitle,
                    onClick = {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareText)
                        context.startActivity(Intent.createChooser(send, shareTitle))
                    },
                    modifier = Modifier.weight(1f),
                )
                CapsuleButton(
                    stringResource(if (copied) R.string.info_copied else R.string.info_copy),
                    onClick = {
                        context.getSystemService(ClipboardManager::class.java)
                            ?.setPrimaryClip(ClipData.newPlainText("Cetchup invite code", code))
                        copied = true
                    },
                    fill = ButtonFill.Outline,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(stringResource(R.string.info_people_title), count = state.members.size.takeIf { it > 0 })
            Column(Modifier.paperCard(padding = 14.dp)) {
                state.members.forEachIndexed { index, member ->
                    val me = member.userId == model.myId
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .semantics(mergeDescendants = true) { }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Monogram(member.name, size = 36.dp)
                        Text(member.name, style = KetchupTheme.type.body, color = colors.ink)
                        if (me) Kicker(stringResource(R.string.info_you))
                    }
                    if (index < state.members.size - 1) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .padding(start = 48.dp)
                                .height(1.dp)
                                .background(colors.rule),
                        )
                    }
                }
            }
        }

        Row(
            Modifier
                .paperCard(padding = 16.dp)
                .pressable { confirmLeave = true }
                .semantics(mergeDescendants = true) { },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ChatIcon(R.drawable.chat_ic_leave, null, colors.ketchupText, size = 22.dp)
            Text(
                stringResource(R.string.info_leave),
                style = KetchupTheme.type.body.copy(fontWeight = FontWeight.SemiBold),
                color = colors.ketchupText,
            )
        }
    }

    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            confirmButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    onLeave()
                }) { Text(stringResource(R.string.info_leave), color = colors.ketchupText, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = { TextButton(onClick = { confirmLeave = false }) { Text(stringResource(R.string.sheet_cancel), color = colors.ink) } },
            title = { Text(stringResource(R.string.info_leave_title, chat.name), style = KetchupTheme.type.serifTitle3, color = colors.ink) },
            text = { Text(stringResource(R.string.info_leave_body), style = KetchupTheme.type.body, color = colors.inkSoft) },
            containerColor = colors.card,
        )
    }
}
