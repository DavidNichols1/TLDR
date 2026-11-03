package com.vibetemp.ketchup.ui.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.Config
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.ui.chat.ChatModel
import com.vibetemp.ketchup.ui.design.Wordmark
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Where the sign-in form starts (previews open the code step with a countdown running). */
data class SignInStart(val email: String = "", val code: String = "", val atCode: Boolean = false, val cooldown: Int = 0)

/**
 * Email, then the emailed code ([Config.OTP_LENGTH] digits), then in (iOS
 * `SignInView`). The account is made on the first code. Supabase sends one
 * code per address a minute, so Resend counts down instead of failing.
 * [api] is null in an offline preview: the buttons do nothing.
 */
@Composable
fun SignInScreen(api: KetchupApi?, start: SignInStart = SignInStart()) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var atCode by rememberSaveable { mutableStateOf(start.atCode) }
    var email by rememberSaveable { mutableStateOf(start.email) }
    var code by rememberSaveable { mutableStateOf(start.code) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var cooldown by rememberSaveable { mutableIntStateOf(start.cooldown) }
    val emailFocus = remember { FocusRequester() }
    val codeFocus = remember { FocusRequester() }

    val trimmedEmail = email.trim()
    val validEmail = "@" in trimmedEmail && "." in trimmedEmail && trimmedEmail.length >= 5
    val phrase = codePhrase()

    // One tick a second while a cooldown runs.
    LaunchedEffect(cooldown > 0) {
        while (cooldown > 0) {
            delay(1_000)
            cooldown -= 1
        }
    }
    LaunchedEffect(atCode) {
        runCatching { if (atCode) codeFocus.requestFocus() else emailFocus.requestFocus() }
    }

    fun sendCode() {
        if (!validEmail || busy || cooldown > 0) return
        val live = api ?: return
        val resending = atCode
        email = trimmedEmail.lowercase()
        busy = true
        error = null
        scope.launch {
            try {
                live.sendCode(email)
                atCode = true
                code = ""
                notice = if (resending) context.getString(R.string.signin_new_code_sent) else null
                cooldown = 60
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = ChatModel.readable(e)
                // "...you can only request this after 22 seconds." counts that down;
                // a 429 that doesn't say counts down the usual minute.
                val seconds = Regex("after (\\d+) seconds").find(e.message.orEmpty())?.groupValues?.get(1)?.toIntOrNull()
                if (seconds != null) cooldown = seconds else if ((e as? ApiException)?.status == 429) cooldown = 60
            } finally {
                busy = false
            }
        }
    }

    fun verify() {
        if (code.length != Config.OTP_LENGTH || busy) return
        val live = api ?: return
        busy = true
        error = null
        scope.launch {
            try {
                // Success sets the session; the root moves on by itself.
                live.verifyCode(email, code)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = ChatModel.readable(e)
                code = ""
            } finally {
                busy = false
            }
        }
    }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .imePadding(),
    ) {
        val minHeight = maxHeight
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = 520.dp)
                    .fillMaxWidth()
                    .heightIn(min = minHeight)
                    .padding(horizontal = 24.dp),
            ) {
                Wordmark(size = 40.dp, drawIn = true, modifier = Modifier.padding(top = 28.dp, bottom = 36.dp))
                AnimatedContent(
                    targetState = atCode,
                    transitionSpec = { fadeIn(Motion.fade()) togetherWith fadeOut(Motion.fade()) },
                    label = "step",
                ) { codeStep ->
                    if (!codeStep) {
                        EmailStep(
                            email = email,
                            onEmail = { email = it },
                            phrase = phrase,
                            canSend = validEmail && cooldown == 0,
                            busy = busy,
                            focus = emailFocus,
                            onSend = ::sendCode,
                        )
                    } else {
                        CodeStep(
                            email = email,
                            code = code,
                            onCode = { new ->
                                val digits = new.filter(Char::isDigit).take(Config.OTP_LENGTH)
                                code = digits
                                if (digits.length == Config.OTP_LENGTH) verify()
                            },
                            phrase = phrase,
                            busy = busy,
                            cooldown = cooldown,
                            focus = codeFocus,
                            onVerify = ::verify,
                            onResend = ::sendCode,
                            onDifferentEmail = {
                                atCode = false
                                code = ""
                                error = null
                                notice = null
                            },
                        )
                    }
                }
                Box(Modifier.padding(top = 14.dp)) {
                    val shown = error
                    if (shown != null) FormError(shown) else notice?.let { FormNotice(it) }
                }
                Spacer(Modifier.weight(1f).heightIn(min = 40.dp))
                Byline(Modifier.padding(bottom = 12.dp))
            }
        }
    }
}

/** "an 8-digit code", "a 6-digit code". */
@Composable
private fun codePhrase(): String {
    val n = Config.OTP_LENGTH
    val an = n.toString().startsWith("8") || n == 11 || n == 18
    return stringResource(if (an) R.string.signin_code_phrase_an else R.string.signin_code_phrase_a, n)
}

@Composable
private fun EmailStep(
    email: String,
    onEmail: (String) -> Unit,
    phrase: String,
    canSend: Boolean,
    busy: Boolean,
    focus: FocusRequester,
    onSend: () -> Unit,
) {
    val colors = KetchupTheme.colors
    Column {
        Text(
            stringResource(R.string.signin_headline),
            style = KetchupTheme.type.serifLargeTitle,
            color = colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            stringResource(R.string.signin_pitch),
            style = KetchupTheme.type.body,
            color = colors.inkSoft,
            modifier = Modifier.padding(top = 10.dp),
        )
        PaperField(
            value = email,
            onValueChange = onEmail,
            placeholder = stringResource(R.string.signin_email_placeholder),
            modifier = Modifier.padding(top = 28.dp),
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Go,
            ),
            keyboardActions = KeyboardActions(onGo = { onSend() }),
            focusRequester = focus,
        )
        BusyCapsule(
            stringResource(R.string.signin_send_code),
            busy = busy,
            onClick = onSend,
            enabled = canSend,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            stringResource(R.string.signin_code_note, phrase),
            style = KetchupTheme.type.footnote,
            color = colors.inkSoft,
            modifier = Modifier.padding(top = 12.dp),
        )
    }
}

@Composable
private fun CodeStep(
    email: String,
    code: String,
    onCode: (String) -> Unit,
    phrase: String,
    busy: Boolean,
    cooldown: Int,
    focus: FocusRequester,
    onVerify: () -> Unit,
    onResend: () -> Unit,
    onDifferentEmail: () -> Unit,
) {
    val colors = KetchupTheme.colors
    val sentTo = stringResource(R.string.signin_sent_to, phrase, email)
    Column {
        Text(
            stringResource(R.string.signin_check_email),
            style = KetchupTheme.type.serifLargeTitle,
            color = colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            buildAnnotatedString {
                val at = sentTo.lastIndexOf(email)
                if (at < 0) {
                    append(sentTo)
                } else {
                    append(sentTo.substring(0, at))
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = colors.ink)) { append(email) }
                    append(sentTo.substring(at + email.length))
                }
            },
            style = KetchupTheme.type.body,
            color = colors.inkSoft,
            modifier = Modifier.padding(top = 10.dp),
        )
        CodeField(
            value = code,
            onValueChange = onCode,
            length = Config.OTP_LENGTH,
            digits = true,
            label = stringResource(R.string.signin_code_label),
            focusRequester = focus,
            modifier = Modifier.padding(top = 28.dp),
            onSubmit = onVerify,
        )
        BusyCapsule(
            stringResource(R.string.signin_sign_in),
            busy = busy,
            onClick = onVerify,
            enabled = code.length == Config.OTP_LENGTH,
            modifier = Modifier.padding(top = 16.dp),
        )
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 18.dp, start = 4.dp, end = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            TextAction(stringResource(R.string.signin_different_email), colors.ink, enabled = true, onClick = onDifferentEmail)
            TextAction(
                if (cooldown > 0) stringResource(R.string.signin_resend_in, cooldown) else stringResource(R.string.signin_resend),
                if (cooldown > 0) colors.inkSoft else colors.ketchupText,
                enabled = !busy && cooldown == 0,
                onClick = onResend,
            )
        }
    }
}

/** A plain text button in subheadline semibold. */
@Composable
fun TextAction(text: String, color: androidx.compose.ui.graphics.Color, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Text(
        text,
        style = KetchupTheme.type.subheadline.copy(fontWeight = FontWeight.SemiBold),
        color = color,
        modifier = modifier
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(vertical = 6.dp),
    )
}

/** "Summaries by Muse Spark, Meta's model". */
@Composable
private fun Byline(modifier: Modifier = Modifier) {
    val model = stringResource(R.string.model_name)
    val line = stringResource(R.string.signin_byline, model)
    Text(
        buildAnnotatedString {
            val at = line.indexOf(model)
            if (at < 0) {
                append(line)
            } else {
                append(line.substring(0, at))
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(model) }
                append(line.substring(at + model.length))
            }
        },
        style = KetchupTheme.type.footnote,
        color = KetchupTheme.colors.inkSoft,
        textAlign = TextAlign.Center,
        modifier = modifier.fillMaxWidth(),
    )
}
