[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory=$false)][string]$DeviceIp, [string]$ApkPath = '', [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ApkPath)) { $ApkPath = Join-Path $project 'builds\CozyFall-debug.apk' }
$adb = 'E:\CodexCache\godot-android-4.7.1\android-sdk\platform-tools\adb.exe'
$package = 'com.holly.cozyfall'
if (!(Test-Path $adb)) { throw "adb not found: $adb" }
if ($ValidateOnly) {
  if (!(Test-Path (Join-Path $project 'export_presets.cfg'))) { throw 'Missing Android export preset.' }
  $manifest = Join-Path $project 'android\build\src\main\AndroidManifest.xml'
  foreach ($pattern in @('android.software.leanback','android.hardware.touchscreen','android:banner','LEANBACK_LAUNCHER','android.intent.category.LAUNCHER','screenOrientation="landscape"')) {
    if (!(Select-String -LiteralPath $manifest -Pattern $pattern -Quiet)) { throw "TV manifest missing required pattern: $pattern" }
  }
  Write-Host 'ValidateOnly passed: adb, export preset, and TV manifest settings are present.'; return
}
if ([string]::IsNullOrWhiteSpace($DeviceIp)) { throw 'DeviceIp is required unless -ValidateOnly is used.' }
if (!(Test-Path $ApkPath)) { throw "APK not found: $ApkPath" }
& $adb connect $DeviceIp
$abi = (& $adb -s $DeviceIp shell getprop ro.product.cpu.abi).Trim()
if ($abi -notmatch 'arm64-v8a|armeabi-v7a') { throw "Unsupported target ABI: $abi" }
if ($PSCmdlet.ShouldProcess($DeviceIp, "install and launch $package")) {
  & $adb -s $DeviceIp install -r $ApkPath
  & $adb -s $DeviceIp shell pm path $package
  & $adb -s $DeviceIp shell monkey -p $package 1
}
