// Top-level build file. The versions live in gradle/libs.versions.toml and
// match AurariaGO's Android app, so this builds with what's on David's Mac.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
