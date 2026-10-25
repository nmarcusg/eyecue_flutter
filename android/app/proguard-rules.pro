# Rules below exist only because a dependency resolves classes reflectively.
# Shrinking stays enabled; nothing here disables R8.

# WorkManager opens its Room-backed database by name: Room's generated lookup
# instantiates androidx.work.impl.WorkDatabase_Impl reflectively, so R8 removing
# or renaming either class crashes startup with
# "Failed to create an instance of class androidx.work.impl.WorkDatabase".
# work-runtime 2.11.2 ships consumer rules meant to cover this; the pin in
# build.gradle.kts already made the runtime and its Room implementation match,
# and this is the narrow keep for the exact class the crash named.
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# Room builds a database's generated `_Impl` off its no-argument constructor via
# reflection (Class.forName(databaseClass.name + "_Impl")), which R8 cannot see.
# Keeping that constructor on every RoomDatabase subclass keeps the generated
# class - and the `_Impl` Room emits next to it - reachable under shrinking.
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}
