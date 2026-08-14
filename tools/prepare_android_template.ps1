[CmdletBinding()]
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$templates = 'C:\Users\Tak\AppData\Roaming\Godot\export_templates\4.7.1.stable'
$zip = Join-Path $templates 'android_source.zip'; $versionFile = Join-Path $templates 'version.txt'
$build = Join-Path $project 'android\build'; $overlay = Join-Path $project 'android\template-overlay'
$godotMarker = Join-Path $project 'android\.build_version'
if (!(Test-Path $zip) -or !(Test-Path $versionFile)) { throw 'Installed Godot 4.7.1 Android source template or version.txt is missing.' }
$version = (Get-Content -Raw $versionFile).Trim()
if ($version -ne '4.7.1.stable') { throw "Unexpected Godot template version: $version" }
if ($ValidateOnly) {
  $manifest = Join-Path $build 'src\main\AndroidManifest.xml'
  $buildMarker = Join-Path $build '.build_version'
  if (!(Test-Path $manifest) -or !(Test-Path $buildMarker) -or !(Test-Path $godotMarker)) { throw 'Prepared Android template or canonical Godot version marker is absent.' }
  foreach ($marker in @($buildMarker, $godotMarker)) {
    if ((Get-Content -Raw $marker).Trim() -ne $version) { throw "Android template version mismatch: $marker" }
  }
  foreach ($pattern in @('android.software.leanback','android.hardware.touchscreen','android:banner','LEANBACK_LAUNCHER','android.intent.category.LAUNCHER')) { if (!(Select-String -LiteralPath $manifest -Pattern $pattern -Quiet)) { throw "Template manifest missing $pattern" } }
  Write-Host 'Prepared Android template validation passed.'; return
}
New-Item -ItemType Directory -Force -Path $build | Out-Null
tar -xf $zip -C $build
Set-Content -LiteralPath (Join-Path $build '.build_version') -Value $version -NoNewline
# Godot's custom-gradle acceptance check resolves this marker through res://android.
# Both generated markers are ignored; the build marker remains for template tooling.
Set-Content -LiteralPath $godotMarker -Value $version -NoNewline
# Keep the 228 MB generated template out of Godot's filesystem scan/import pipeline.
Set-Content -LiteralPath (Join-Path $build '.gdignore') -Value '' -NoNewline
Copy-Item -LiteralPath (Join-Path $overlay 'AndroidManifest.xml') -Destination (Join-Path $build 'src\main\AndroidManifest.xml') -Force
$drawable = Join-Path $build 'res\drawable-nodpi'; New-Item -ItemType Directory -Force -Path $drawable | Out-Null
Copy-Item -LiteralPath (Join-Path $overlay 'res\drawable-nodpi\cozyfall_tv_banner.png') -Destination $drawable -Force
& $PSCommandPath -ValidateOnly
