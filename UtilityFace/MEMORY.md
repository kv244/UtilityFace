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
- Background (`resources/drawables/background.png`) is a hand-picked
  176×176 1-bit crop from `manyBg.png` (an untracked 2048×2048 spritesheet
  of bold B&W geometric art — not committed, unused by the build), chosen
  by scoring candidate crops against where each text label/icon/the
  compass ring actually renders on screen.
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
