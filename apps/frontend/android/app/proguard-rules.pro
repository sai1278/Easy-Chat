# Flutter Wrapper Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.internal.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.stat.Stat { *; }

# Flutter Play Store Deferred Components Suppressions
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Flutter Secure Storage & AndroidX Crypto Keep Rules
-keep class com.it_effekt.** { *; }
-keep class com.it_effekt.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# OkHttp3 / Dio Networking Keep Rules
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**

# Geolocator Keep Rules
-keep class com.baseflow.geolocator.** { *; }

# Isar Database & Native Binaries
-keep class io.isar.** { *; }

# Protobuf & gRPC Serialization
-keep class com.google.protobuf.** { *; }
