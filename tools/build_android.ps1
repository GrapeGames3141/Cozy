[CmdletBinding()]
param([switch]$Release, [int]$TimeoutSeconds = 600)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$godot = 'E:\CodexCache\godot-android-4.7.1\godot\Godot_v4.7.1-stable_win64_console.exe'
$sdk = 'E:\CodexCache\godot-android-4.7.1\android-sdk'
$jdk = 'E:\CodexCache\godot-android-4.7.1\jdk\jdk-17.0.20+8'
$cache = 'E:\CodexCache\cozyfall\gradle'
$logDir = Join-Path $project '.runtime_validation\android_build_logs'
New-Item -ItemType Directory -Force -Path $cache, (Join-Path $project 'builds'), $logDir | Out-Null
if (!(Test-Path $godot) -or !(Test-Path $sdk) -or !(Test-Path $jdk)) { throw 'Godot, Android SDK, or JDK is missing; see docs/android.md.' }
& (Join-Path $PSScriptRoot 'prepare_android_template.ps1')
$env:GRADLE_USER_HOME = $cache
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME = $jdk
$env:PATH = (Join-Path $sdk 'platform-tools') + ';' + (Join-Path $jdk 'bin') + ';' + $env:PATH
$preset = 'Android Fire TV'
$exportFlag = if ($Release) { '--export-release' } else { '--export-debug' }
$apkRelative = if ($Release) { 'builds\CozyFall-release.apk' } else { 'builds\CozyFall-debug.apk' }
$apk = Join-Path $project $apkRelative
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logDir "godot-$stamp.stdout.log"
$stderr = Join-Path $logDir "godot-$stamp.stderr.log"
$pidLog = Join-Path $logDir "godot-$stamp.pids.log"
$started = Get-Date
$previousApk = if (Test-Path $apk) { $item = Get-Item $apk; [pscustomobject]@{ LastWriteTimeUtc = $item.LastWriteTimeUtc; Length = $item.Length; Sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash } } else { $null }
$trackedPids = [System.Collections.Generic.HashSet[int]]::new()

function Get-TaskDescendants([int]$RootProcessId) {
  $all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
  $childrenByParent = @{}
  foreach ($item in $all) {
    $parentId = [int]$item.ParentProcessId
    if (!$childrenByParent.ContainsKey($parentId)) { $childrenByParent[$parentId] = @() }
    $childrenByParent[$parentId] += $item
  }
  $found = @(); $pending = [System.Collections.Generic.Queue[int]]::new(); $pending.Enqueue($RootProcessId)
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

function Record-TaskDescendants([int]$RootProcessId, [string]$LogPath, $Tracked) {
  $descendants = @(Get-TaskDescendants $RootProcessId)
  foreach ($descendant in $descendants) { [void]$Tracked.Add([int]$descendant.ProcessId) }
  $lines = @($descendants | ForEach-Object { "Descendant PID=$($_.ProcessId) Name=$($_.Name) Parent=$($_.ParentProcessId)" })
  if ($lines.Count -gt 0) { Add-Content -LiteralPath $LogPath -Value $lines }
  return $descendants
}

function Test-FreshApk([string]$ApkPath, $Previous) {
  if (!(Test-Path $ApkPath)) { return $false }
  $current = Get-Item $ApkPath
	if ($current.Length -le 0 -or $current.LastWriteTimeUtc -lt $started.ToUniversalTime()) { return $false }
  $currentHash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash
  if ($null -ne $Previous -and $current.LastWriteTimeUtc -le $Previous.LastWriteTimeUtc -and $current.Length -eq $Previous.Length -and $currentHash -eq $Previous.Sha256) { return $false }
  return $true
}

function Test-ExportLogsSuccess {
  if (!(Test-Path $stdout) -or !(Test-Path $stderr)) { return $false }
  return ((Select-String -LiteralPath $stdout -Pattern 'DONE.*export' -Quiet) -and (Get-Item $stderr).Length -eq 0)
}

function Test-ApkContents([string]$ApkPath) {
  $aapt2 = Join-Path $sdk 'build-tools\36.1.0\aapt2.exe'
  $apksigner = Join-Path $sdk 'build-tools\36.1.0\apksigner.bat'
  $zipalign = Join-Path $sdk 'build-tools\36.1.0\zipalign.exe'
  foreach ($tool in @($aapt2, $apksigner, $zipalign)) { if (!(Test-Path $tool)) { throw "Required Android validation tool is missing: $tool" } }
  $badging = & $aapt2 dump badging $ApkPath 2>&1; if ($LASTEXITCODE -ne 0) { throw 'aapt2 badging validation failed.' }
  $badgingText = $badging -join "`n"
  if ($badgingText -notmatch "package: name='com\.grapegames\.cozyfall'" -or $badgingText -notmatch 'arm64-v8a' -or $badgingText -notmatch 'armeabi-v7a' -or $badgingText -notmatch "uses-feature-not-required: name='android\.software\.leanback'" -or $badgingText -notmatch "uses-feature-not-required: name='android\.hardware\.touchscreen'") { throw 'APK package, required dual ABI, or explicitly optional TV feature is missing.' }
  $manifest = & $aapt2 dump xmltree $ApkPath --file AndroidManifest.xml 2>&1; if ($LASTEXITCODE -ne 0) { throw 'aapt2 manifest validation failed.' }
  foreach ($required in @('android:banner', 'LEANBACK_LAUNCHER', 'android.intent.category.LAUNCHER', 'screenOrientation.*=0')) { if (($manifest -join "`n") -notmatch $required) { throw "APK manifest missing required TV field: $required" } }
  $signature = & $apksigner verify --verbose --min-sdk-version 24 $ApkPath 2>&1; if ($LASTEXITCODE -ne 0 -or ($signature -join "`n") -notmatch 'Verified using v2 scheme.*true') { throw 'APK v2 signature verification failed.' }
  & $zipalign -c -v 4 $ApkPath; if ($LASTEXITCODE -ne 0) { throw 'APK zipalign verification failed.' }
}

function Test-ApkArtifact([string]$ApkPath) {
	if (!(Test-FreshApk $ApkPath $previousApk)) { throw 'APK is missing, empty, or not freshly produced by this export.' }
	Test-ApkContents $ApkPath
}

function Stop-LingeringGodot([int]$RootProcessId, $Descendants) {
  Stop-Process -Id $RootProcessId -Force -ErrorAction SilentlyContinue
  foreach ($descendant in $Descendants) {
    if ($null -ne $descendant -and $descendant.Name -match '^(Godot.*|conhost)$') { Stop-Process -Id ([int]$descendant.ProcessId) -Force -ErrorAction SilentlyContinue }
  }
}

$godotArguments = "--headless --path `"$project`" --quit $exportFlag `"$preset`" `"$apk`""
$proc = Start-Process -FilePath $godot -ArgumentList $godotArguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
$processHandle = $proc.Handle # Preserve ExitCode availability after redirected PowerShell 5 runs.
[void]$trackedPids.Add($proc.Id)
Set-Content -LiteralPath $pidLog -Value "Godot PID=$($proc.Id) started=$started"
try {
  $deadline = $started.AddSeconds($TimeoutSeconds)
  while (!$proc.HasExited -and (Get-Date) -lt $deadline) {
	$descendants = @(Record-TaskDescendants $proc.Id $pidLog $trackedPids)
	$gradleRemains = @($descendants | Where-Object { $_.Name -match '^(java|gradle|gradlew)(\.exe)?$' })
	if ((Test-ExportLogsSuccess) -and $gradleRemains.Count -eq 0 -and (Test-FreshApk $apk $previousApk)) {
		Test-ApkArtifact $apk
		Stop-LingeringGodot $proc.Id $descendants
		Add-Content -LiteralPath $pidLog -Value "Validated fresh APK after export DONE; terminated only lingering tracked Godot/conhost processes."
		Write-Host "Android export complete and verified: $apk"
		return
	}
    Start-Sleep -Seconds 2
  }
  Record-TaskDescendants $proc.Id $pidLog $trackedPids | Out-Null
  if (!$proc.HasExited) { throw "Godot Android export timed out after $TimeoutSeconds seconds." }
  if ($proc.ExitCode -ne 0) { throw "Godot Android export failed ($($proc.ExitCode))." }
	Test-ApkArtifact $apk
	Start-Sleep -Seconds 1
	$remaining = @(Record-TaskDescendants $proc.Id $pidLog $trackedPids)
	if ($remaining.Count -gt 0) { throw "Task-started export descendants remain after Godot exit: $(($remaining.ProcessId -join ','))" }
	Add-Content -LiteralPath $pidLog -Value "Success: no task-started descendants remain."
  Write-Host "Android export complete: $apk"
}
catch {
	foreach ($trackedPid in ($trackedPids | Sort-Object -Descending)) { Stop-Process -Id $trackedPid -Force -ErrorAction SilentlyContinue }
  Add-Content -LiteralPath $pidLog -Value "Cleanup invoked after failure: $($_.Exception.Message)"
  throw "$($_.Exception.Message) Logs: $stdout ; $stderr ; $pidLog"
}
