# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase / Ktor / OkHttp
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.ktor.**
-keep class io.ktor.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}

# Keep app_links entry points
-keep class com.llfbandit.app_links.** { *; }

# Play Core (referenced by Flutter engine deferred components — not used in this app)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
