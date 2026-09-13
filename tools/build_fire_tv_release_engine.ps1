[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$DeviceCheckOnly,
  [string]$DeviceIp = '192.168.1.75',
  [int]$TimeoutSeconds = 600
)

# This diagnostic build keeps the existing Godot debug signing route (and therefore
# its installed sideload identity), but swaps only the ignored generated debug AAR
# for Godot's official template_release AAR while exporting. No keystore, password,
# or credential is read, copied, or stored here.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$template = Join-Path $project 'android\build'
$godot = 'E:\CodexCache\godot-android-4.7.1\godot\Godot_v4.7.1-stable_win64_console.exe'
$sdk = 'E:\CodexCache\godot-android-4.7.1\android-sdk'
$jdk = 'E:\CodexCache\godot-android-4.7.1\jdk\jdk-17.0.20+8'
$cache = 'E:\CodexCache\cozyfall\gradle'
$resultApk = Join-Path $project 'builds\CozyFall-firetv-release-engine.apk'
$validationDir = Join-Path $project '.runtime_validation\fire_tv_release_engine'
$expectedArmV7BuildId = 'c1c5db343a780348be4a6d7a10175e2425214c01'

New-Item -ItemType Directory -Force -Path $validationDir, (Split-Path $resultApk -Parent), $cache | Out-Null
if (!(Test-Path $godot) -or !(Test-Path $sdk) -or !(Test-Path $jdk)) { throw 'Godot, Android SDK, or JDK is missing.' }
$env:GRADLE_USER_HOME = $cache
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME = $jdk
$env:PATH = (Join-Path $sdk 'platform-tools') + ';' + (Join-Path $jdk 'bin') + ';' + $env:PATH

function Get-TaskDescendants([int]$RootProcessId) {
  $all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
  $childrenByParent = @{}
  foreach ($item in $all) {
    $parentId = [int]$item.ParentProcessId
    if (!$childrenByParent.ContainsKey($parentId)) { $childrenByParent[$parentId] = @() }
    $childrenByParent[$parentId] += $item
  }
  $found = @(); $pending = [System.Collections.Generic.Queue[int]]::new()
  if ($RootProcessId -gt 0) { $pending.Enqueue($RootProcessId) }
  while ($pending.Count -gt 0) {
    $parent = $pending.Dequeue()
    if (!$childrenByParent.ContainsKey($parent)) { continue }
    foreach ($child in $childrenByParent[$parent]) {
      if ($null -eq $child -or [int]$child.ProcessId -le 0) { continue }
      $found += $child; $pending.Enqueue([int]$child.ProcessId)
    }
  }
  return $found
}

function Record-Descendants([int]$RootProcessId, [string]$PidLog, $TrackedPids) {
  $descendants = @(Get-TaskDescendants $RootProcessId)
  foreach ($child in $descendants) {
    [void]$TrackedPids.Add([int]$child.ProcessId)
    Add-Content -LiteralPath $PidLog -Value "Descendant PID=$($child.ProcessId) Name=$($child.Name) Parent=$($child.ParentProcessId)"
  }
  return $descendants
}

function Stop-TrackedProcesses([int]$RootProcessId, $TrackedPids, [string]$PidLog) {
  Record-Descendants $RootProcessId $PidLog $TrackedPids | Out-Null
  foreach ($taskPid in @($TrackedPids | Sort-Object -Descending)) {
    if ($taskPid -gt 0) { Stop-Process -Id $taskPid -Force -ErrorAction SilentlyContinue }
  }
  Add-Content -LiteralPath $PidLog -Value 'Cleanup stopped only the root and its recorded descendants.'
}

function Invoke-ReleaseEngineExport {
  $stdout = Join-Path $validationDir 'godot_release_engine.stdout.log'
  $stderr = Join-Path $validationDir 'godot_release_engine.stderr.log'
  $pidLog = Join-Path $validationDir 'godot_release_engine.pids.log'
  Remove-Item -LiteralPath $stdout, $stderr, $pidLog, $resultApk -Force -ErrorAction SilentlyContinue
  $arguments = "--headless --path `"$project`" --quit --export-debug `"Android Fire TV`" `"$resultApk`""
  $proc = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  $processHandle = $proc.Handle
  $trackedPids = [System.Collections.Generic.HashSet[int]]::new(); [void]$trackedPids.Add($proc.Id)
  Set-Content -LiteralPath $pidLog -Value "Godot root PID=$($proc.Id) started=$(Get-Date -Format o)"
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  try {
    while (!$proc.HasExited -and (Get-Date) -lt $deadline) {
      $descendants = @(Record-Descendants $proc.Id $pidLog $trackedPids)
      $gradleRemains = @($descendants | Where-Object { $_.Name -match '^(java|gradle|gradlew)(\.exe)?$' })
      $done = (Test-Path $resultApk) -and (Select-String -LiteralPath $stdout -Pattern 'DONE.*export' -Quiet) -and (Get-Item $stderr).Length -eq 0
      if ($done -and $gradleRemains.Count -eq 0) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        foreach ($child in $descendants) {
          if ($child.Name -match '^(Godot.*|conhost)$') { Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue }
        }
        Add-Content -LiteralPath $pidLog -Value 'Export DONE; stopped only lingering tracked Godot/conhost processes after Gradle completed.'
        return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; PidLog = $pidLog; RootPid = $proc.Id }
      }
      Start-Sleep -Seconds 2
    }
    Record-Descendants $proc.Id $pidLog $trackedPids | Out-Null
    if (!$proc.HasExited) { throw "Godot release-engine export timed out after $TimeoutSeconds seconds." }
    if ($proc.ExitCode -ne 0) { throw "Godot release-engine export failed with exit code $($proc.ExitCode)." }
    if (!(Test-Path $resultApk) -or !(Select-String -LiteralPath $stdout -Pattern 'DONE.*export' -Quiet) -or (Get-Item $stderr).Length -ne 0) { throw 'Godot release-engine export completed without a clean fresh APK.' }
    return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; PidLog = $pidLog; RootPid = $proc.Id }
  } catch {
    Stop-TrackedProcesses $proc.Id $trackedPids $pidLog
    throw "$($_.Exception.Message) Logs: $stdout ; $stderr ; $pidLog"
  }
}

function Get-CertificateDigest([string]$ApkPath, [string]$ApkSigner) {
  $output = & $ApkSigner verify --print-certs --min-sdk-version 24 $ApkPath 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Could not read APK signing certificate: $ApkPath" }
  foreach ($line in $output) {
    if ($line -match '^Signer #1 certificate SHA-256 digest:\s+([0-9A-Fa-f:]+)$') { return $Matches[1].Replace(':', '').ToUpperInvariant() }
  }
  throw "APK signing certificate digest was not reported: $ApkPath"
}

function Test-ReleaseEngineApk([string]$ApkPath, [string]$ReferenceDebugApk) {
  $aapt2 = Join-Path $sdk 'build-tools\36.1.0\aapt2.exe'
  $apksigner = Join-Path $sdk 'build-tools\36.1.0\apksigner.bat'
  $zipalign = Join-Path $sdk 'build-tools\36.1.0\zipalign.exe'
  $readelf = Get-ChildItem -LiteralPath (Join-Path $sdk '.temp') -Recurse -Filter 'llvm-readelf.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  foreach ($tool in @($aapt2, $apksigner, $zipalign, $readelf)) { if ([string]::IsNullOrWhiteSpace($tool) -or !(Test-Path $tool)) { throw "Required validation tool is missing: $tool" } }
  $badging = & $aapt2 dump badging $ApkPath 2>&1
  if ($LASTEXITCODE -ne 0) { throw 'aapt2 badging validation failed.' }
  $badgingText = $badging -join "`n"
  foreach ($required in @("package: name='com.grapegames.cozyfall'", 'native-code:.*arm64-v8a.*armeabi-v7a', "uses-feature-not-required: name='android.software.leanback'", "uses-feature-not-required: name='android.hardware.touchscreen'")) {
    if ($badgingText -notmatch $required) { throw "APK badging missing required field: $required" }
  }
  $manifest = & $aapt2 dump xmltree $ApkPath --file AndroidManifest.xml 2>&1
  if ($LASTEXITCODE -ne 0) { throw 'aapt2 manifest validation failed.' }
  $manifestText = $manifest -join "`n"
  foreach ($required in @('android:banner', 'LEANBACK_LAUNCHER', 'android.intent.category.LAUNCHER', 'screenOrientation.*=0')) {
    if ($manifestText -notmatch $required) { throw "APK manifest missing required TV field: $required" }
  }
  $signature = & $apksigner verify --verbose --min-sdk-version 24 $ApkPath 2>&1
  if ($LASTEXITCODE -ne 0 -or ($signature -join "`n") -notmatch 'Verified using v2 scheme.*true') { throw 'APK v2 signature validation failed.' }
  & $zipalign -c -v 4 $ApkPath | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'APK zipalign validation failed.' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
  $enginePath = Join-Path $validationDir 'libgodot_android.armeabi-v7a.release.so'
  try {
    foreach ($entry in $archive.Entries) {
      if ($entry.FullName -match '^(source_assets|previews|tests|tools|docs|android)/') { throw "Development-only content was packaged: $($entry.FullName)" }
    }
    $engineEntry = $archive.GetEntry('lib/armeabi-v7a/libgodot_android.so')
    if ($null -eq $engineEntry) { throw 'Release-engine APK is missing ARMv7 libgodot_android.so.' }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($engineEntry, $enginePath, $true)
  } finally { $archive.Dispose() }
  $buildIdOutput = & $readelf -n $enginePath 2>&1
  if (($buildIdOutput -join "`n") -notmatch $expectedArmV7BuildId) { throw "ARMv7 Godot engine Build ID is not the official release value $expectedArmV7BuildId." }
  $referenceDigest = Get-CertificateDigest $ReferenceDebugApk $apksigner
  $releaseDigest = Get-CertificateDigest $ApkPath $apksigner
  if ($referenceDigest -ne $releaseDigest) { throw 'Release-engine APK signing certificate differs from the installed debug identity.' }
}

function Install-And-CheckFireTv([string]$ApkPath) {
  $adb = Join-Path $sdk 'platform-tools\adb.exe'
  & $adb connect $DeviceIp | Out-Null
  $abi = (& $adb -s $DeviceIp shell getprop ro.product.cpu.abi).Trim()
  if ($abi -ne 'armeabi-v7a') { throw "Expected Fire TV armeabi-v7a target, received: $abi" }
  & $adb -s $DeviceIp install -r $ApkPath | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'adb install -r failed.' }
  & $adb -s $DeviceIp shell monkey -p com.grapegames.cozyfall 1 | Set-Content -LiteralPath (Join-Path $validationDir 'fire_tv_start.txt')
  Start-Sleep -Seconds 15
  & $adb -s $DeviceIp shell dumpsys activity activities | Set-Content -LiteralPath (Join-Path $validationDir 'fire_tv_activity.txt')
  & $adb -s $DeviceIp logcat -d -v threadtime -t 600 | Select-String -Pattern 'com.grapegames.cozyfall|GodotLib.setup|ANR|Application Not Responding|Fatal signal' | Set-Content -LiteralPath (Join-Path $validationDir 'fire_tv_relevant_logcat.txt')
  $shot = Join-Path $validationDir 'fire_tv_after_15s.png'
  $remoteShot = '/sdcard/Download/cozyfall_release_engine_capture.png'
  try {
    & $adb -s $DeviceIp shell screencap -p $remoteShot
    if ($LASTEXITCODE -ne 0) { throw 'Fire TV screencap command failed.' }
    & $adb -s $DeviceIp pull $remoteShot $shot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'adb pull of Fire TV screenshot failed.' }
  } finally {
    & $adb -s $DeviceIp shell rm -f $remoteShot | Out-Null
  }
  if (!(Test-Path $shot) -or (Get-Item $shot).Length -lt 1024) { throw 'Fire TV screenshot was not captured.' }
  Add-Type -AssemblyName System.Drawing
  $bitmap = [System.Drawing.Bitmap]::FromFile($shot)
  $hasVisiblePixel = $false
  try {
    for ($y = 0; $y -lt $bitmap.Height -and !$hasVisiblePixel; $y += 64) {
      for ($x = 0; $x -lt $bitmap.Width; $x += 64) {
        $pixel = $bitmap.GetPixel($x, $y)
        if (($pixel.R + $pixel.G + $pixel.B) -gt 18) { $hasVisiblePixel = $true; break }
      }
    }
  } finally { $bitmap.Dispose() }
  if (!$hasVisiblePixel) { throw 'Fire TV screenshot is all black after the 15-second launch check.' }
  $relevantLog = Get-Content -LiteralPath (Join-Path $validationDir 'fire_tv_relevant_logcat.txt') -Raw -ErrorAction SilentlyContinue
  if ($relevantLog -match 'GodotLib\.setup.*ANR|Application Not Responding.*cozyfall') { throw 'Fire TV log contains a new Cozy Fall startup ANR.' }
  return $shot
}

$debugAar = Join-Path $template 'libs\debug\godot-lib.template_debug.aar'
$releaseAar = Join-Path $template 'libs\release\godot-lib.template_release.aar'
$debugBackup = Join-Path $validationDir 'godot-lib.template_debug.original.aar'
if ($DeviceCheckOnly) {
  if (!(Test-Path $resultApk)) { throw "Release-engine APK is absent: $resultApk" }
  Test-ReleaseEngineApk $resultApk (Join-Path $project 'builds\CozyFall-debug.apk')
  $screenshot = Install-And-CheckFireTv $resultApk
  Write-Host "Existing release-engine APK validated and checked on Fire TV: $screenshot"
  return
}
try {
  & (Join-Path $PSScriptRoot 'prepare_android_template.ps1')
  foreach ($file in @($debugAar, $releaseAar)) { if (!(Test-Path $file)) { throw "Required Godot engine AAR is missing: $file" } }
  $originalDebugHash = (Get-FileHash -LiteralPath $debugAar -Algorithm SHA256).Hash
  Copy-Item -LiteralPath $debugAar -Destination $debugBackup -Force
  Copy-Item -LiteralPath $releaseAar -Destination $debugAar -Force
  $export = Invoke-ReleaseEngineExport
} finally {
  if (Test-Path $debugBackup) {
    Copy-Item -LiteralPath $debugBackup -Destination $debugAar -Force
    if ($null -ne $originalDebugHash -and (Get-FileHash -LiteralPath $debugAar -Algorithm SHA256).Hash -ne $originalDebugHash) { throw 'Original generated debug AAR did not restore byte-for-byte.' }
  }
}

Test-ReleaseEngineApk $resultApk (Join-Path $project 'builds\CozyFall-debug.apk')
$sha = (Get-FileHash -LiteralPath $resultApk -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $validationDir 'release_engine_result.txt') -Value "APK=$resultApk`nSHA256=$sha`nARMV7_GODOT_BUILD_ID=$expectedArmV7BuildId`nPID_LOG=$($export.PidLog)`nDEBUG_AAR_RESTORED_SHA256=$originalDebugHash"
Write-Host "Release-engine Fire TV APK validated: $resultApk"
if ($Install) {
  $screenshot = Install-And-CheckFireTv $resultApk
  Write-Host "Fire TV launch checked after 15 seconds: $screenshot"
}
