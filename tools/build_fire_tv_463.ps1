[CmdletBinding()]
param(
  [switch]$Install,
  [string]$DeviceIp = '192.168.1.75:5555',
  [int]$TimeoutSeconds = 600,
  # The deployed Fire TV app uses Godot's normal 4.6 debug identity (97DC...).
  # This path is referenced only; no key material or password is read or copied.
  [string]$DebugKeystorePath = 'C:/Users/Tak/AppData/Roaming/Godot/keystores/debug.keystore'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$cache = 'E:\CodexCache\godot-android-4.6.3'
$godot = Join-Path $cache 'godot\Godot_v4.6.3-stable_win64_console.exe'
$templates = Join-Path $cache 'export_templates\4.6.3.stable'
$sdk = 'E:\CodexCache\godot-android-4.7.1\android-sdk'
$jdk = 'E:\CodexCache\godot-android-4.7.1\jdk\jdk-17.0.20+8'
$stage = 'E:\CodexCache\cozyfall\fire_tv_463_stage'
$gradleCache = 'E:\CodexCache\cozyfall\gradle_463'
$resultApk = Join-Path $project 'builds\CozyFall-firetv-4.6.3.apk'
$validation = Join-Path $project '.runtime_validation\fire_tv_463'
New-Item -ItemType Directory -Force -Path $validation, $gradleCache, (Split-Path $resultApk -Parent) | Out-Null
foreach ($item in @($godot, (Join-Path $templates 'android_source.zip'), (Join-Path $templates 'version.txt'), $sdk, $jdk)) { if (!(Test-Path $item)) { throw "Required 4.6.3 fallback input is absent: $item" } }
$version = (Get-Content -Raw (Join-Path $templates 'version.txt')).Trim()
if ($version -ne '4.6.3.stable') { throw "Unexpected 4.6 template version: $version" }
$env:GRADLE_USER_HOME = $gradleCache; $env:ANDROID_HOME = $sdk; $env:ANDROID_SDK_ROOT = $sdk; $env:JAVA_HOME = $jdk
$env:PATH = (Join-Path $sdk 'platform-tools') + ';' + (Join-Path $jdk 'bin') + ';' + $env:PATH

# Godot reads Android tool locations from the per-version EditorSettings resource,
# not from the child process environment.  Keep the durable SDK/JDK on E:, use the
# normal Godot debug keystore by reference only, and restore the prior settings at
# the end of this invocation.
$editorSettings = Join-Path $env:APPDATA 'Godot\editor_settings-4.6.tres'
$editorSettingsBackup = Join-Path $validation 'editor_settings-4.6.before.tres'
$hadEditorSettings = Test-Path $editorSettings
if ($hadEditorSettings) { Copy-Item -LiteralPath $editorSettings -Destination $editorSettingsBackup -Force }
else { Remove-Item -LiteralPath $editorSettingsBackup -Force -ErrorAction SilentlyContinue }
function Set-GodotEditorSetting([string]$Path, [string]$Key, [string]$Value) {
  $text = if (Test-Path $Path) { Get-Content -LiteralPath $Path -Raw } else { '[gd_resource type="EditorSettings" format=3]' + "`n`n[resource]`n" }
  $escaped = [Regex]::Escape($Key)
  $line = "$Key = `"$($Value.Replace('\', '\\'))`""
  if ($text -match "(?m)^$escaped\s*=") { $text = [Regex]::Replace($text, "(?m)^$escaped\s*=.*$", $line) } else { $text = $text.TrimEnd() + "`n$line`n" }
  Set-Content -LiteralPath $Path -Value $text -NoNewline
}

function Copy-StageItem([string]$Relative) {
  $source = Join-Path $project $Relative; $destination = Join-Path $stage $Relative
  if (!(Test-Path $source)) { throw "Missing required runtime source: $source" }
  New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}
function Get-TaskDescendants([int]$RootProcessId) {
  $all = @(Get-CimInstance Win32_Process); $map = @{}
  foreach ($item in $all) { $parent = [int]$item.ParentProcessId; if (!$map.ContainsKey($parent)) { $map[$parent] = @() }; $map[$parent] += $item }
  $found = @(); $queue = [System.Collections.Generic.Queue[int]]::new(); if ($RootProcessId -gt 0) { $queue.Enqueue($RootProcessId) }
  while ($queue.Count -gt 0) { $parent = $queue.Dequeue(); if (!$map.ContainsKey($parent)) { continue }; foreach ($child in $map[$parent]) { if ($null -eq $child -or [int]$child.ProcessId -le 0) { continue }; $found += $child; $queue.Enqueue([int]$child.ProcessId) } }
  return $found
}
function Test-Apk([string]$Apk) {
  $aapt2 = Join-Path $sdk 'build-tools\36.1.0\aapt2.exe'; $signer = Join-Path $sdk 'build-tools\36.1.0\apksigner.bat'; $zipalign = Join-Path $sdk 'build-tools\36.1.0\zipalign.exe'
  $badging = (& $aapt2 dump badging $Apk) -join "`n"
  foreach ($required in @("package: name='com.holly.cozyfall'", 'native-code:.*arm64-v8a.*armeabi-v7a', "uses-feature-not-required: name='android.software.leanback'", "uses-feature-not-required: name='android.hardware.touchscreen'")) { if ($badging -notmatch $required) { throw "APK validation missing: $required" } }
  $manifest = (& $aapt2 dump xmltree $Apk --file AndroidManifest.xml) -join "`n"
  foreach ($required in @('android:banner','LEANBACK_LAUNCHER','android.intent.category.LAUNCHER','screenOrientation.*=0')) { if ($manifest -notmatch $required) { throw "APK manifest missing: $required" } }
  $verified = (& $signer verify --verbose --min-sdk-version 24 $Apk) -join "`n"; if ($verified -notmatch 'Verified using v2 scheme.*true') { throw 'APK v2 signing validation failed.' }
  & $zipalign -c -v 4 $Apk | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'APK zipalign validation failed.' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Apk); $so = Join-Path $validation 'libgodot_android.armeabi-v7a.so'
  try { foreach ($entry in $archive.Entries) { if ($entry.FullName -match '^(source_assets|previews|tests|tools|docs|android)/') { throw "Development-only archive entry: $($entry.FullName)" } }; [IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry('lib/armeabi-v7a/libgodot_android.so'), $so, $true) } finally { $archive.Dispose() }
  $binaryText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($so))
  if ($binaryText -notmatch 'psa_crypto_init') { throw '4.6.3 ARMv7 engine is missing the expected PSA crypto path.' }
  if ($binaryText -notmatch '/dev/urandom') { throw '4.6.3 ARMv7 engine lacks /dev/urandom evidence.' }
  if ($binaryText -match '/dev/random') { throw '4.6.3 ARMv7 engine still contains a blocking /dev/random reference.' }
}
function Get-CertificateDigest([string]$Apk, [string]$ApkSigner) {
  $output = & $ApkSigner verify --print-certs --min-sdk-version 24 $Apk 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Could not inspect signing certificate: $Apk" }
  foreach ($line in $output) {
    if ($line -match '^Signer #1 certificate SHA-256 digest:\s+([0-9A-Fa-f:]+)$') { return $Matches[1].Replace(':', '').ToUpperInvariant() }
  }
  throw "Signing certificate digest was not reported: $Apk"
}
function Test-SigningIdentity([string]$Apk) {
  $apksigner = Join-Path $sdk 'build-tools\36.1.0\apksigner.bat'
  $actual = Get-CertificateDigest $Apk $apksigner
  $expected = '97DCAC80C34AB36C9B1E0DA8CEF5DC87C14911FFDB26D30AA0BC039F1E8BE42B'
  if ($actual -ne $expected) { throw "4.6.3 APK signing certificate must be the deployed Godot debug identity ($expected), got $actual." }
}
function Install-ValidatedApk([string]$Apk) {
  $adb = Join-Path $sdk 'platform-tools\adb.exe'
  & $adb connect $DeviceIp | Out-Null
  $installedPaths = @(& $adb -s $DeviceIp shell pm path com.holly.cozyfall 2>&1)
  if ($LASTEXITCODE -eq 0 -and $installedPaths.Count -gt 0 -and ($installedPaths -join "`n") -match '(?m)^package:(.+\.apk)$') {
    $installedApk = Join-Path $validation 'installed_base.apk'
    Remove-Item -LiteralPath $installedApk -Force -ErrorAction SilentlyContinue
    & $adb -s $DeviceIp pull $Matches[1].Trim() $installedApk | Out-Null
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $installedApk)) { throw 'Could not pull the currently installed public base APK for certificate comparison; refusing install -r.' }
    $expected = Get-CertificateDigest $Apk (Join-Path $sdk 'build-tools\36.1.0\apksigner.bat')
    $installed = Get-CertificateDigest $installedApk (Join-Path $sdk 'build-tools\36.1.0\apksigner.bat')
    if ($expected -ne $installed) { throw "Installed package certificate ($installed) differs from this APK ($expected). Refusing install -r to preserve app data. For the one-time certificate migration, back up the save, explicitly uninstall, install, and restore outside this wrapper." }
    & $adb -s $DeviceIp install -r $Apk
  } else {
    & $adb -s $DeviceIp install $Apk
  }
  if ($LASTEXITCODE -ne 0) { throw 'ADB installation failed.' }
}
function Check-Device([string]$Apk, [int]$Attempt) {
  $adb = Join-Path $sdk 'platform-tools\adb.exe'; & $adb connect $DeviceIp | Out-Null
  & $adb -s $DeviceIp shell am force-stop com.holly.cozyfall
  $launchUtc = (Get-Date).ToUniversalTime().ToString('o')
  & $adb -s $DeviceIp shell monkey -p com.holly.cozyfall 1 | Out-Null
  Start-Sleep -Seconds 15
  $remote = "/sdcard/Download/cozyfall_463_$Attempt.png"; $shot = Join-Path $validation "cold_launch_$Attempt.png"
  try { & $adb -s $DeviceIp shell screencap -p $remote; & $adb -s $DeviceIp pull $remote $shot | Out-Null } finally { & $adb -s $DeviceIp shell rm -f $remote | Out-Null }
  $activityPath = Join-Path $validation "cold_launch_$Attempt.activity.txt"
  $activity = (& $adb -s $DeviceIp shell dumpsys activity activities) -join "`n"
  Set-Content -LiteralPath $activityPath -Value "CapturedUtc=$launchUtc`n$activity"
  $logPath = Join-Path $validation "cold_launch_$Attempt.logcat.txt"
  $tail = @(& $adb -s $DeviceIp logcat -d -v threadtime | Select-Object -Last 1600)
  Set-Content -LiteralPath $logPath -Value ("LaunchUtc=$launchUtc`nLogTailLines=$($tail.Count)`n" + ($tail -join "`n"))
  Add-Type -AssemblyName System.Drawing; $image = [Drawing.Bitmap]::FromFile($shot); $visible = $false
  try { for ($y=0; $y -lt $image.Height -and !$visible; $y+=64) { for ($x=0; $x -lt $image.Width; $x+=64) { $pixel=$image.GetPixel($x,$y); if (($pixel.R+$pixel.G+$pixel.B) -gt 18) { $visible=$true; break } } } } finally { $image.Dispose() }
  $log = Get-Content -Raw $logPath
  if ($activity -notmatch '(?m)(mResumedActivity|mCurrentFocus).*com\.holly\.cozyfall') { throw "Fire TV cold launch $Attempt did not resume/focus Cozy Fall (profile chooser or another activity is foreground)." }
  $appPid = ((& $adb -s $DeviceIp shell pidof com.holly.cozyfall) -join '').Trim()
  $packageAnr = '(?is)(?:ANR|Application Not Responding).{0,300}com\.holly\.cozyfall|com\.holly\.cozyfall.{0,300}(?:ANR|Application Not Responding)'
  $godotAnr = '(?is)GodotLib\.setup.{0,300}(?:ANR|Application Not Responding)|(?:ANR|Application Not Responding).{0,300}GodotLib\.setup'
  $fatalForApp = if ($appPid) { '(?is)Fatal signal.{0,300}(?:\b' + [Regex]::Escape($appPid) + '\b|com\.holly\.cozyfall)' } else { $false }
  if (!$visible -or $log -match $packageAnr -or $log -match $godotAnr -or ($fatalForApp -and $log -match $fatalForApp)) { throw "Fire TV cold launch $Attempt did not reach a rendered scene." }
}

$staticValidationPassed = $false
try {
  Set-GodotEditorSetting $editorSettings 'export/android/java_sdk_path' $jdk
  Set-GodotEditorSetting $editorSettings 'export/android/android_sdk_path' $sdk
  # The wrapper does not inspect or copy key material. Godot/apksigner read the
  # referenced key to sign the APK, using the normal debug-key configuration.
  Set-GodotEditorSetting $editorSettings 'export/android/debug_keystore' $DebugKeystorePath
  Set-GodotEditorSetting $editorSettings 'export/android/debug_keystore_user' 'androiddebugkey'
  Set-GodotEditorSetting $editorSettings 'export/android/debug_keystore_pass' 'android'
  if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  foreach ($relative in @('assets','data','scenes','scripts','android\template-overlay','project.godot','export_presets.cfg')) { Copy-StageItem $relative }
  $stagedProject = Join-Path $stage 'project.godot'; $projectText = Get-Content -Raw $stagedProject; $projectText = $projectText.Replace('"4.7"', '"4.6"'); Set-Content -LiteralPath $stagedProject -Value $projectText -NoNewline
  $build = Join-Path $stage 'android\build'; New-Item -ItemType Directory -Force -Path $build | Out-Null; tar -xf (Join-Path $templates 'android_source.zip') -C $build
  Set-Content -LiteralPath (Join-Path $build '.build_version') -Value $version -NoNewline; Set-Content -LiteralPath (Join-Path $stage 'android\.build_version') -Value $version -NoNewline; Set-Content -LiteralPath (Join-Path $build '.gdignore') -Value '' -NoNewline
  Copy-Item -LiteralPath (Join-Path $stage 'android\template-overlay\AndroidManifest.xml') -Destination (Join-Path $build 'src\main\AndroidManifest.xml') -Force
  $bannerDir = Join-Path $build 'res\drawable-nodpi'; New-Item -ItemType Directory -Force -Path $bannerDir | Out-Null; Copy-Item -LiteralPath (Join-Path $stage 'android\template-overlay\res\drawable-nodpi\cozyfall_tv_banner.png') -Destination $bannerDir -Force
  $stdout = Join-Path $validation 'godot_463.stdout.log'; $stderr = Join-Path $validation 'godot_463.stderr.log'; $pidLog = Join-Path $validation 'godot_463.pids.log'; Remove-Item $stdout,$stderr,$pidLog,$resultApk -Force -ErrorAction SilentlyContinue
  $arguments = "--headless --path `"$stage`" --quit --export-debug `"Android Fire TV`" `"$resultApk`""; $proc = Start-Process -FilePath $godot -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden; $handle=$proc.Handle; Set-Content $pidLog "Godot root PID=$($proc.Id)"; $tracked=@($proc.Id); $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  while (!$proc.HasExited -and (Get-Date) -lt $deadline) { $children=@(Get-TaskDescendants $proc.Id); $tracked += @($children|ForEach-Object{[int]$_.ProcessId}); if ((Test-Path $resultApk) -and (Select-String $stdout -Pattern 'DONE.*export' -Quiet) -and (Get-Item $stderr).Length -eq 0 -and @($children|Where-Object{$_.Name -match '^(java|gradle|gradlew)(\.exe)?$'}).Count -eq 0) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; foreach($child in $children){if($child.Name -match '^(Godot.*|conhost)$'){Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue}}; break }; Start-Sleep -Seconds 2 }
  Get-TaskDescendants $proc.Id | ForEach-Object { $tracked += [int]$_.ProcessId }; Add-Content $pidLog ($tracked|Sort-Object -Unique|ForEach-Object{"Tracked PID=$_"})
  if (!(Test-Path $resultApk) -or !(Select-String $stdout -Pattern 'DONE.*export' -Quiet) -or (Get-Item $stderr).Length -ne 0) { foreach($taskPid in $tracked|Sort-Object -Descending|Select-Object -Unique){Stop-Process -Id $taskPid -Force -ErrorAction SilentlyContinue}; throw "4.6.3 export failed. Logs: $stdout ; $stderr" }
  Test-Apk $resultApk
  Test-SigningIdentity $resultApk
  $staticValidationPassed = $true
  if ($Install) { Install-ValidatedApk $resultApk; foreach($attempt in 1..3){Check-Device $resultApk $attempt} }
  $hash=(Get-FileHash $resultApk -Algorithm SHA256).Hash; Set-Content (Join-Path $validation 'result.txt') "APK=$resultApk`nSHA256=$hash`nEDITOR_SHA256=E39986A178D585CE7AC198FB8DE6EA436366DC0CC00E594810C2E3E104C04B90`nTEMPLATES_SHA256=3FBE2C0E2DEC9D537AB9EC97BCF8DA91DCF23357FC51F67092DD068D839290A8"
} catch {
  # Keep a statically valid artifact if connectivity, foreground activity, or
  # device validation fails. Only a failed export/static signing validation may
  # remove the APK produced by this invocation.
  if (-not $staticValidationPassed) { Remove-Item -LiteralPath $resultApk -Force -ErrorAction SilentlyContinue }
  throw
} finally {
  if ($hadEditorSettings -and (Test-Path $editorSettingsBackup)) { Copy-Item -LiteralPath $editorSettingsBackup -Destination $editorSettings -Force }
  elseif (Test-Path $editorSettings) { Remove-Item -LiteralPath $editorSettings -Force }
}
