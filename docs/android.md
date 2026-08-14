# Android / Fire TV

`export_presets.cfg` enables Godot's checked-in custom Gradle template. Its operative manifest is `android/build/src/main/AndroidManifest.xml`; it declares both ordinary and LEANBACK launcher behavior, landscape orientation, no touchscreen requirement, a TV banner, and `armeabi-v7a` plus `arm64-v8a`.

Install a debug APK with `tools/install_fire_tv.ps1 -DeviceIp <ip>`. The script connects with adb, checks the target ABI, installs with `-r`, verifies `com.holly.cozyfall`, and launches the activity. It does not hold credentials or signing keys.

Godot export templates and an Android SDK/JDK are required for a real APK export. The checked-in custom manifest is intentionally conservative: this MVP is a normal TV activity, not an Android DreamService.

`tools/prepare_android_template.ps1` uses the installed `android_source.zip`, writes the matching `4.7.1.stable` marker inside `android/build/.build_version` and at Godot's canonical generated lookup `android/.build_version`, then overlays the tracked manifest and 320×180 banner. Both markers and the 228 MB Gradle template are ignored. The generated build directory keeps `.gdignore`, so it stays out of Godot's normal import scan while the canonical marker permits custom-template export acceptance.

The current custom-template `builds/CozyFall-debug.apk` is directly verified as TV-ready: package `com.holly.cozyfall`, a 320×180 banner, touchscreen/leanback optional features, ordinary and LEANBACK launchers, landscape orientation, and both arm64-v8a plus armeabi-v7a. `aapt2`, `apksigner` v2 verification, and `zipalign` all pass. It is debug-signed for sideload/development validation, not store distribution.

`tools/build_android.ps1` now adds `--quit`, uses a bounded 10-minute export, E:-based ignored logs, PID recording, and task-owned cleanup. It pins `ANDROID_HOME` and `ANDROID_SDK_ROOT` to the same E:-based SDK and `JAVA_HOME` to the E:-based JDK before launch, resolving the prior Gradle SDK conflict. It requires a fresh APK plus matching export-DONE/empty-stderr logs and validates package, ABIs, TV manifest fields, v2 signature, and zip alignment before reporting success. If Godot has exported successfully but lingers, it terminates only its tracked Godot/conhost processes after no Java/Gradle descendants remain.

## Fire TV release-engine sideload diagnostic build

`tools/build_fire_tv_release_engine.ps1` is the repeatable 4.7.1 diagnostic path. It reproduced the pre-project entropy startup stall on this Fire TV, so it is retained for diagnosis rather than deployment. In the ignored generated template only, it backs up `libs/debug/godot-lib.template_debug.aar`, temporarily substitutes the installed official `template_release` AAR, and uses Godot's normal `standardDebug` export/signing path. It restores the debug AAR byte-for-byte in `finally`.

The wrapper rejects outputs unless they retain `com.holly.cozyfall`, the TV manifest/banner, both requested ABIs, zip alignment, a v2 signature, no development-only archive directories, and the known official ARMv7 release-engine Build ID `c1c5db343a780348be4a6d7a10175e2425214c01`. It also requires the resulting certificate digest to match `CozyFall-debug.apk`. Add `-Install` to install with `adb -r` on the configured Fire TV, launch it, wait 15 seconds, and retain screenshot/activity/log evidence under ignored `.runtime_validation\fire_tv_release_engine`; an all-black capture is an explicit failed startup check, never a success.

## Official 4.6.3 Fire TV fallback

`tools/build_fire_tv_463.ps1` stages only runtime project files in E:-local cache, changes the staged feature marker to 4.6, and exports with verified official Godot 4.6.3 editor/templates. It leaves the 4.7 project and Windows target unchanged, validates APK TV metadata and ABI/signing/alignment/exclusions, and extracts the exact packaged ARMv7 engine to require its `psa_crypto_init` path plus `/dev/urandom` while rejecting `/dev/random`.

The 4.6.3 fallback is the deployed Fire TV solution. Its retained APK is `builds/CozyFall-firetv-4.6.3.apk`, SHA-256 `4D3B5047C206D8A7EBF5225A848A88CCF0CEF6FA6799A13254DBE826F8E99C25`, signed by the Godot debug certificate `97DCAC80...F1E8BE42B`. Migration restored the exact saved JSON SHA-256 `83AC1B...08B28`. Attempts 2–5 visually reached the porch scene with zero ANR/native-error matches; attempt 1 was intercepted by the Fire TV profile chooser. The final D-pad focus check passed and Cozy Fall remained running.

The deployed 97DC Godot debug identity is the wrapper's normal build baseline; no migration flag or old C263 APK reference is needed. With `-Install`, the wrapper first pulls only the installed app's public base APK and compares its public signing certificate to the candidate. It uses `adb install -r` only when they match; an absent package receives a normal install. A mismatch is refused with one-time migration guidance—this wrapper never auto-uninstalls, clears app data, or searches/copies keystores. It retains timestamped logcat tails (without clearing device-wide logs), requires the resumed/focused activity to be `com.holly.cozyfall`, and limits ANR/fatal rejection to Cozy Fall/Godot evidence before performing three force-stop cold-launch screenshot checks.
