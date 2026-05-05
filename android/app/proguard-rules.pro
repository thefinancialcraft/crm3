# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Hive
-keep class com.hive.** { *; }
-keep @com.google.gson.annotations.SerializedName class * { *; }

# Supabase / Realtime / Postgrest
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# OkHttp (used by http package)
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Flutter Local Notifications
-keep class com.dexterous.** { *; }

# Flutter Background Service
-keep class id.flutter.flutter_background_service.** { *; }

# In-App Update
-keep class com.google.android.play.core.** { *; }

# flutter_inappwebview
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.**

# phone_state
-keep class dev.fluttercommunity.plus.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**
-keepattributes *Annotation*
-keepattributes Signature

# OkHttp TLS platform providers (not used on Android, safe to ignore)
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**