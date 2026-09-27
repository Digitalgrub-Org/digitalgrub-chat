# Flutter's engine entry points are reached reflectively from native code.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite and secure storage plugins register through reflection.
-keep class com.tekartik.sqflite.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Flutter references Play Core deferred-component APIs that this app does not
# use and does not bundle. Without this, R8 fails on the missing classes.
-dontwarn com.google.android.play.core.**

# Keep annotations so plugin registration survives shrinking.
-keepattributes *Annotation*

# Line numbers make Play Console crash reports readable while still
# obfuscating names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
