# Cozy Fall local rules

- Keep all durable source, generated assets, previews, builds, and validation logs in this `E:` project directory.
- `source_assets/` is immutable. Regenerate runtime derivatives only with `tools/derive_assets.gd`.
- Use Godot 4.7.1 Compatibility. For every Godot run, record task-started PIDs; after it exits, inspect and clean only processes/dialogs started by this task.
- Do not commit `.godot/`, builds, credentials, keystores, or validation scratch data.
