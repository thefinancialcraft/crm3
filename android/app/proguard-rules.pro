# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# call_log plugin
-keep class com.example.call_log.**
-keepclassmembers class com.example.call_log.** { *; }

# Supabase
-keep class io.supabase.** { *; }
-keep class com.google.crypto.tink.** { *; }

# Flutter background service
-keep class id.flutter.flutter_background_service.** { *; }
-keep class com.dexterous.** { *; }

# Don't obfuscate serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep permission annotations
-keepattributes RuntimeVisibleAnnotations
-keep class androidx.annotation.** { *; }

# Google Play Core (optional dependency for dynamic features)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**