# Cozy Fall

**Cozy Fall** is a remote-first, painterly fall-decorating sandbox for TV. Place decor around a cottage porch, welcome visitors, or enter a calm Ambient Mode.

## Run

Use Godot 4.7.1 Compatibility:

```powershell
& 'E:\CodexCache\godot-android-4.7.1\godot\Godot_v4.7.1-stable_win64_console.exe' --path 'E:\AI Projects\Holly\cozyfall'
```

Controls are intentionally simple: D-pad navigates/moves, Select confirms or places, and Back cancels/returns. The app includes no accounts, currency, unlocks, advertising, or backend.

## Assets

The supplied originals are retained byte-for-byte in `source_assets/generated/`. Run `tools/derive_assets.gd` headlessly to regenerate the background, 20 decor cuts, and six alpha-clean visitor cutouts in `assets/`.

## Validation

```powershell
& 'E:\CodexCache\godot-android-4.7.1\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tests/test_runner.gd
& .\tools\install_fire_tv.ps1 -ValidateOnly
```

`tools/build_android.ps1` uses E:-based Gradle/cache locations. A debug signed APK is suitable for device validation; create and supply a release keystore before distribution.
