# Cozy Fall local rules

- Keep all durable source, generated assets, previews, builds, and validation logs in this `E:` project directory.
- `source_assets/` is immutable. Regenerate runtime derivatives only with `tools/derive_assets.gd`.
- Use Godot 4.7.1 Compatibility. For every Godot run, record task-started PIDs; after it exits, inspect and clean only processes/dialogs started by this task.
- Do not commit `.godot/`, builds, credentials, keystores, or validation scratch data.
- Play Store assets in `store/` are generated — change `tools/generate_store_assets.py` and re-run it rather than editing the PNGs or descriptions in place.
- The AdMob banner must stay on Google's test unit while the app is in closed testing. Both `TODO(ads-live)` markers move together.
- A local Android export rewrites `project.godot` into Godot's normalized form; that diff is expected. Do not try to commit an `[admob]` section — Godot strips it on load, and `scripts/ci/godot-export-android.sh` injects the AdMob app ID before each export instead.
