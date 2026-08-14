# Android / Fire TV

`export_presets.cfg` enables Godot's checked-in custom Gradle template. Its operative manifest is `android/build/src/main/AndroidManifest.xml`; it declares both ordinary and LEANBACK launcher behavior, landscape orientation, no touchscreen requirement, a TV banner, and `armeabi-v7a` plus `arm64-v8a`.

Install a debug APK with `tools/install_fire_tv.ps1 -DeviceIp <ip>`. The script connects with adb, checks the target ABI, installs with `-r`, verifies `com.holly.cozyfall`, and launches the activity. It does not hold credentials or signing keys.

Godot export templates and an Android SDK/JDK are required for a real APK export. The checked-in custom manifest is intentionally conservative: this MVP is a normal TV activity, not an Android DreamService.

`tools/prepare_android_template.ps1` uses the installed `android_source.zip`, writes `.build_version` from the matching `version.txt` (`4.7.1.stable`), then overlays the tracked manifest and 320×180 banner. This avoids committing the 228 MB generated Gradle template.

The current custom-template `builds/CozyFall-debug.apk` is directly verified as TV-ready: package `com.holly.cozyfall`, a 320×180 banner, touchscreen/leanback optional features, ordinary and LEANBACK launchers, landscape orientation, and both arm64-v8a plus armeabi-v7a. `aapt2`, `apksigner` v2 verification, and `zipalign` all pass. It is debug-signed for sideload/development validation, not store distribution.

`tools/build_android.ps1` now adds `--quit`, uses a bounded 10-minute export, E:-based ignored logs, PID recording, and task-owned cleanup. It pins `ANDROID_HOME` and `ANDROID_SDK_ROOT` to the same E:-based SDK and `JAVA_HOME` to the E:-based JDK before launch, resolving the prior Gradle SDK conflict. It requires a fresh APK plus matching export-DONE/empty-stderr logs and validates package, ABIs, TV manifest fields, v2 signature, and zip alignment before reporting success. If Godot has exported successfully but lingers, it terminates only its tracked Godot/conhost processes after no Java/Gradle descendants remain.
