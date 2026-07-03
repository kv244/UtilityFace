# UtilityFace — Session Memory

## Target
Garmin Instinct 2 only (Surf Edition included, same hardware/manifest
product id). `instinct2x` and `instinct2s` were both dropped — see State.

## Toolchain
Monkey C only. No C/Python/ASM path exists for Connect IQ. SDK Manager +
`monkeyc` CLI + `simulator.exe` + `monkeydo.bat`, scripted via the
PowerShell commands in README.md. CI mirrors this headlessly using
[connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli)
— see `.github/workflows/release.yml`.

## State (as of 2026-07-02)
- Built and verified repeatedly against the real SDK in the simulator
  (screenshotted and visually checked after each change, not just
  compiled).
- `manifest.xml` products: `instinct2` only. `instinct2s` (resources +
  product entry) and `instinct2x` (product entry, which was also throwing
  an "Invalid device id" warning on every build) were both removed.
- `UtilityFaceView.mc` draws: time, seconds, HR (main text + subscreen
  badge on devices with one), SpO2, altitude (mountain icon), ambient temp
  (thermometer icon), battery (lightning-bolt icon), daily step count
  (sneaker icon — replaced the old BT-connection status field), date, and
  a compass ring with cardinal ticks.
- **Live heading, done properly**: `Sensor` + `Background` permissions,
  `HeadingServiceDelegate.mc` ((:background)-annotated `ServiceDelegate`
  subclass) reads `Sensor.getInfo().heading` and calls `Background.exit()`
  on a temporal event registered in `UtilityFaceApp.onStart()` (5-minute
  interval requested; Garmin throttles the actual cadence, so this is a
  slow drift-corrected refresh, not a live compass). `UtilityFaceApp` is
  itself `(:background)`-annotated (required once any background code
  exists — the OS instantiates the App class in the background slice too,
  to call `getServiceDelegate()`); `UtilityFaceView` carries
  `(:typecheck(disableBackgroundCheck))` so strict typecheck doesn't try
  to validate Graphics/WatchUi calls against the background-restricted
  scope. `getHeading()` reads `Storage.getValue("backgroundHeading")`
  first, falling back to `Activity.getActivityInfo().currentHeading`.
  This was a real dead end before it worked: a plain
  `Sensor.getInfo().heading` call in `onUpdate` doesn't compile for a
  `watchface` app type at all (manifest validator requires `Background`
  permission alongside `Sensor`), and getting the annotations right took
  three iterations — see git history / PR discussion for the exact
  compiler errors if this needs touching again.
- **Heading refresh is now visible on screen**, next to O2 (subscreen
  layout only — the non-subscreen layout has "HR xx" inline at x=24 on
  the same row with essentially no gap before O2, doesn't fit there).
  Real motivation: there was previously no way to tell when the
  background heading last actually updated, since Garmin throttles the
  wake interval and the screen doesn't redraw the instant new data
  lands. `HeadingServiceDelegate.onTemporalEvent()` now captures
  `System.getClockTime()` at the moment it reads the sensor (not in
  `onBackgroundData`, which can be delayed if the watch face isn't
  active when the background slice finishes) and bundles
  `{"heading", "hour", "minute"}` through `Background.exit()`.
  `onBackgroundData` unpacks and stores all three under separate
  `Storage` keys. `drawHeadingSyncTime` in the view draws a small "+"
  icon (`icon_synctime.png`) + "HH:MM", or "--:--" before the first
  background wake ever lands.
  **Real bug found and fixed**: the payload dictionary originally used
  Symbol keys (`:heading`, `:hour`, `:minute`), which type-check fine as
  `Application.PropertyKeyType` but crashed `Background.exit()` at
  runtime every single time with `Unexpected Type Error: Failed invoking
  <symbol>` — silently, since a background-slice crash doesn't surface
  as an app crash, it just means `onBackgroundData` never runs. Root
  cause confirmed (not guessed) by building a temporary debug build with
  `System.println` tracing at every step, driving the simulator's
  "Background Events" dialog via the raw Win32 menu API
  (`GetMenu`/`GetSubMenu`/`WM_COMMAND`, then `BM_CLICK` on the dialog's
  OK button — far more reliable than UI Automation clicks for this
  simulator), and reading the symbolicated stack trace, which pointed
  straight at the `Background.exit(payload)` line. `Background.exit()`'s
  own doc comment whitelists String/Number/Float/Boolean/Char/Long/
  Double/Array/Dictionary for the data it carries across the background/
  foreground boundary — Symbol isn't on that list, even though it's a
  valid `Application.PropertyKeyType` at compile time. Switched all three
  keys to Strings (`"heading"`, `"hour"`, `"minute"`) in both
  `HeadingServiceDelegate.onTemporalEvent` and
  `UtilityFaceApp.onBackgroundData`, rebuilt, retriggered a background
  event, and confirmed a real `HH:MM` now renders in place of "--:--".
- **WaveDetector**: a separate companion project at `../WaveDetector`
  (sibling to this folder, its own manifest/jungle/source), build output
  named `B2C3D4E5.PRG` (first 8 hex chars of its own manifest app UUID,
  same convention as `A1B2C3D4.PRG` here — see
  `REVERSE_ENGINEERING_A_PRG.md`). A plain Connect IQ `watch-app` (not a
  watch face) prototyping accelerometer-based
  motion/wave detection via `Sensor.registerSensorDataListener` (25 Hz,
  `{:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}}`
  — this exact options dict and the `accelerometerData.x/y/z` field access
  pattern were cross-checked against Garmin's own bundled `PitchCounter`
  SDK sample, not guessed). Heuristic: EMA-smoothed acceleration-magnitude
  deviation from resting gravity (1000 mG), hysteresis threshold-crossing
  counts one "wave" per high-then-low-then-high cycle. Explicitly not a
  validated surf algorithm, just a working starting point. SELECT resets
  the count. Verified building and running in the simulator (shows
  "listening" + live magnitude readout); did not verify actual wave
  counting against real motion (simulator has no accelerometer input
  device).
- Background is a hand-picked 176×176 1-bit crop from `manyBg.png` (an
  untracked 2048×2048 spritesheet of bold B&W geometric art — not
  committed, unused by the build), chosen by scoring candidate crops
  against where each text label/icon/the compass ring actually renders on
  screen.
- **Background now rotates**: one full 360° turn per day, 15°/hour.
  `resources/drawables/bg_h00.png`..`bg_h23.png` are 24 pre-rotated
  variants (generated from the original background via PIL, rotated
  around center, re-thresholded to 1-bit -- `background.png` itself is
  gone, superseded by `bg_h00.png` which is pixel-identical to it).
  `UtilityFaceView.loadBackgroundForHour` swaps `mBackground` to the
  current hour's variant, but only reloads when the hour actually
  changes. Two real dead ends got hit and confirmed by crashing the
  simulator (not assumed) before landing here:
  1. `Dc.drawBitmap2` + `Graphics.AffineTransform` (real-time rotation of
     a single bitmap) is documented in the general Toybox API but throws
     a runtime "Symbol Not Found" crash on this device/SDK -- a `has`
     guard around it compiles fine and correctly detects the gap
     (confirmed it doesn't get compiled away), but the underlying
     capability just isn't there.
  2. Preloading all 24 pre-rotated bitmaps in `onLayout` throws "Out Of
     Memory" -- decoded bitmaps are expensive enough that the ~256KB
     heap doesn't stretch to 24 resident copies. Only ever keep one
     loaded.
  Verified by comparing a debug build that draws background-only against
  the pre-generated reference PNG for the current hour -- exact shape/
  position match, not just "looks rotated".
- Legibility fix: every `drawText` call fills a solid black background
  (not transparent), and the compass ring/ticks draw a black halo pass
  before the white stroke. Needed because the background has large
  solid-white regions that would otherwise make white UI elements
  invisible where they overlap.
- Build output renamed `utilityface.prg` → `A1B2C3D4.PRG` (first 8 hex
  chars of the manifest app UUID) to match Garmin's on-device naming
  convention. See `REVERSE_ENGINEERING_A_PRG.md` for why, plus a structural
  decompile of this project's own binary.
- CI/CD (`.github/workflows/release.yml`): builds with `monkeyc -r`
  (stripped release build) on every push touching source/resources/
  manifest/jungle, publishes a GitHub Release with the PRG attached only
  if the build succeeds. Needs `GARMIN_USERNAME`, `GARMIN_PASSWORD`,
  `CIQ_DEVELOPER_KEY_B64` repo secrets — already configured, several green
  runs confirmed. Only builds/releases UtilityFace, not WaveDetector.
- The README's local build command also passes `-r` now, same as CI and
  WaveDetector — verified byte-identical section layout (no Symbols
  section) between the local `UtilityFace/A1B2C3D4.PRG` and the one CI
  publishes. Drop `-r` locally if a dev build with a symbol table is
  needed for debugging (see `REVERSE_ENGINEERING_A_PRG.md`'s walkthrough,
  which intentionally uses a dev build for exactly that reason).
- Launcher icon is still the original placeholder (black circle, white "U").

## Next steps
1. `manyBg.png` (4.2 MB) sits untracked in `resources/drawables/`, unused
   by the build — decide whether to keep it as source reference (maybe
   move it outside `resources/` so it's unambiguously not a build input)
   or delete it.
2. Swap the placeholder launcher icon for a real asset before store
   submission (carried over from the original scaffold, still not done).
3. WaveDetector has no CI/release workflow of its own yet — copy/adapt
   `.github/workflows/release.yml` if it needs one.
4. WaveDetector's threshold/EMA constants (`THRESHOLD_HIGH`/`_LOW`,
   `EMA_ALPHA`, `GRAVITY_MG`) are unvalidated guesses — need tuning against
   real accelerometer logs from actual wave motion, which requires
   on-device testing (the simulator has no accelerometer input).
5. Multi-device support (`instinct2s`/`instinct2x`) was deliberately
   dropped, not just deferred — revisit only if there's a concrete reason
   to widen the target again.
