# Google Play release

Cozy Fall ships to Play as an Android App Bundle built by
[`.github/workflows/deploy-android.yml`](../.github/workflows/deploy-android.yml),
which calls [`scripts/ci/godot-export-android.sh`](../scripts/ci/godot-export-android.sh)
and uploads the result to the **closed testing** track (`alpha`).

To change track later, edit `PLAY_TRACK` at the top of the workflow. The API
names are `internal`, `alpha` (closed), `beta` (open), `production`, or a custom
track's own name — they do not always match the Play Console UI labels.

Package name: `com.grapegames.cozyfall` — this is permanent once the first bundle is
uploaded. `versionCode` is the GitHub Actions run number and `versionName` is
`1.<run number>`, so every push to `main` produces a strictly increasing build.

## Required repository secrets

Set these under *Settings → Secrets and variables → Actions*. The workflow fails
fast with a named error if any is empty.

| Secret | What it is |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The release keystore, base64-encoded (`base64 -w0 release.keystore`). Whitespace is stripped before decoding, and a decode under 100 bytes is rejected. |
| `KEY_ALIAS` | Key alias inside that keystore. |
| `KEYSTORE_PASSWORD` | Store and key password (the export uses one value for both). |
| `SERVICE_ACCOUNT_JSON` | Play Console service-account JSON, pasted whole. Needs *Release apps to testing tracks* on this app. |
| `COZYFALL_ADMOB_ANDROID_APP_ID` | Optional. AdMob app ID (`ca-app-pub-…~…`). Falls back to Google's sample app ID, so the build still succeeds without it. |

Keep the keystore itself out of the repo — `.gitignore` refuses `*.keystore`,
`*.jks`, and `*service-account*.json`. Losing it means losing the ability to
update the app, unless Play App Signing holds the upload key.

## Draft app: the first release

A Play app that has never had a release rolled out is a *draft app*. The API
refuses to create a live release on one:

```
Only releases with status draft may be created on draft app.
```

So `PLAY_RELEASE_STATUS` is `draft`. CI builds, signs, uploads the bundle and
creates a **draft release** on the closed track; you then review and roll it out
from the Console. Once one release has actually been rolled out, the app leaves
draft state and you can set `PLAY_RELEASE_STATUS: completed` for hands-off
rollout on every push.

The upload itself needs no manual step — the API binds the package name on its
first successful upload. If you see `Package not found: <package>`, the package
in the workflow does not match the app in your Play account; it is not a
sequencing problem.

Whatever key signs the first uploaded bundle becomes the permanent upload key,
so `ANDROID_KEYSTORE_BASE64` must hold the real release keystore before the
first successful run. To build one locally instead:

```bash
ANDROID_SDK_ROOT="$HOME/Android/Sdk" \
VERSION_CODE=1 VERSION_NAME=1.0 SKIP_DEBUG_APK=1 \
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=<alias> \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password> \
./scripts/ci/godot-export-android.sh
```

The bundle lands at `builds/android/CozyFall.aab`. The script validates package
name, `versionCode`, and `versionName` against the real manifest using Google's
Bundletool before it reports success, so a silently mispackaged bundle fails the
build rather than reaching Play.

A local run leaves `project.godot` rewritten in Godot's normalized form: the
editor reformats it on import and the AdMob plugin appends its translation list.
That is harmless — review and keep the change, or `git checkout project.godot`.

Note that `project.godot` deliberately carries **no** `[admob]` section. The
AdMob editor plugin strips `general/android/app_id` whenever Godot loads the
project, so committing it does not stick. Instead `set_project_android_app_id`
in the export script writes the section immediately before each export, which is
what produces the `com.google.android.gms.ads.APPLICATION_ID` manifest entry.

## What the build does

- Downloads Godot 4.7.1 and its export templates, pinned by `android/.build_version`.
- Downloads the Poing AdMob v5.0.0 Android binaries into `addons/admob/android/bin`
  (~20 MB, cached, gitignored) and refuses to export if the AAR is missing.
- Unzips `android_source.zip` into `android/build` rather than calling
  `--install-android-build-template`, which silently no-ops in headless Godot.
- Overlays `android/play-release.gradle` and `android/proguard-godot-play.pro`
  onto the generated Gradle project: R8 shrinking plus uncompressed native libs
  so 16 KB page-size devices can map `libgodot.so`.
- Exports the `Android Play` preset as an AAB for `arm64-v8a` and `armeabi-v7a`,
  minSdk 24, targetSdk 36.

## Store listing assets

Everything Play asks for is generated into `store/` by
`tools/generate_store_assets.py` from committed sources — the leaf mark in
`assets/icon.svg` and the runtime captures in `previews/`. Re-run it after
changing either:

```bash
python3 tools/generate_store_assets.py
```

| Play field | File |
| --- | --- |
| App icon (512×512) | `store/icon_512.png` |
| Feature graphic (1024×500) | `store/feature_graphic_1024x500.png` |
| Phone screenshots (4 × 1920×1080) | `store/screenshots/phone/` |
| TV banner (1280×720) | `store/tv_banner_1280x720.png` |
| Short description (≤80) | `store/listing/short_description.txt` |
| Full description (≤4000) | `store/listing/full_description.txt` |
| Release notes (≤500) | `store/listing/whatsnew/whatsnew-en-US` |

The workflow passes `whatsNewDirectory: store/listing/whatsnew`, so release notes
travel with each upload. The descriptions and graphics are set once in Play
Console by hand; the API upload does not carry them.

The same four screenshots satisfy the phone slot and the 7"/10" tablet slots.
Cozy Fall is landscape-only, so all of them are 16:9 landscape.

## Still to do by hand in Play Console

These are required before the app can leave draft, and none of them are things
CI can set:

- **Privacy policy URL.** Mandatory, because the app serves ads and the bundle
  declares `AD_ID`. Use the existing Grapegames policy:

  `https://patguettler.github.io/privacy-policy.html`

  It already covers Cozy Fall through its "any future apps under the same
  developer account" clause, so no edit is strictly required — though adding
  Cozy Fall to the named list (source: the `patguettler.github.io` repo) makes
  the coverage obvious to a reviewer.
- **Data safety form.** Declare what the AdMob SDK collects — at minimum the
  advertising ID, and device/app diagnostics.
- **Ads declaration.** The app contains ads. Answer yes.
- **Content rating questionnaire.** Cozy Fall has no violence, purchases, or
  user interaction; expect an Everyone rating.
- **Target audience.** If you declare a child audience, `child_directed` in
  `config/admob.example.json` must flip to `true` and the config in
  `scripts/ci/godot-export-android.sh` must match, or the listing and the ad
  requests disagree.
- **Form factors.** The bundle declares `LEANBACK_LAUNCHER`, so opt into the
  Android TV form factor if you want the TV listing too.

## Ads

AdMob publisher ID is `pub-2846735043546429`, already authorized by
`app-ads.txt` at the root of `patguettler.github.io`. Cozy Fall's eventual live
ad unit sits under that same publisher, so no `app-ads.txt` change is needed.

The banner is Google's **official test unit**
(`ca-app-pub-3940256099942544/6300978111`), wired in
[`autoload/ad_bar_service.gd`](../autoload/ad_bar_service.gd) and written into
`config/admob.json` by CI. Serving live ads to a closed test violates AdMob's
invalid-traffic policy, so this stays as-is until the app is in open testing or
production. Both places are marked `TODO(ads-live)`; switching over means
returning the configured unit from `AdBarService.banner_unit_id()` and sourcing
it from a secret in `write_admob_config`.

The bar renders through the native AdMob view anchored to the bottom of the
window, and the scene reserves matching space via `banner_height_changed` so no
decor or button ever sits under it. Ambient Mode calls
`AdBarService.set_suppressed(true)`, which hides the banner along with the rest
of the chrome — an ambient screen left running all evening shows no ad.
