# ── Flutter engine ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── Plugin registrant (généré par Flutter) ────────────────────────────────────
-keep class com.example.netprobe.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# ── flutter_background_service ────────────────────────────────────────────────
-keep class id.flutter.flutter_background_service.** { *; }
-dontwarn id.flutter.flutter_background_service.**

# ── flutter_local_notifications ───────────────────────────────────────────────
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ── geolocator ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ── permission_handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── sqflite ───────────────────────────────────────────────────────────────────
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# ── connectivity_plus ─────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

# ── network_info_plus ────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.network_info.** { *; }
-dontwarn dev.fluttercommunity.plus.network_info.**

# ── device_info_plus ──────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.device_info.** { *; }
-dontwarn dev.fluttercommunity.plus.device_info.**

# ── battery_plus ──────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.battery.** { *; }
-dontwarn dev.fluttercommunity.plus.battery.**

# ── share_plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# ── package_info_plus ─────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-dontwarn dev.fluttercommunity.plus.packageinfo.**

# ── shared_preferences ────────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ── h3_flutter ────────────────────────────────────────────────────────────────
-keep class com.example.h3_flutter.** { *; }
-dontwarn com.example.h3_flutter.**

# ── Dart JNI / native interop ─────────────────────────────────────────────────
-keep class com.google.** { *; }
-dontwarn com.google.**

# ── Règles générales Android ──────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
