# UtilityFace — Session Memory

## Target
Garmin Instinct 2 (Surf Edition prioritized, same hardware as base Instinct 2)
+ Instinct 2X. Instinct 2S intentionally dropped for now — see State.

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
- `manifest.xml` products: `instinct2`, `instinct2x`. The `instinct2s`
  product entry and its `resources-instinct2s/` folder were removed.
- `UtilityFaceView.mc` draws: time, seconds, HR (main text + subscreen
  badge on devices with one), SpO2, altitude (mountain icon), ambient temp
  (thermometer icon), battery (lightning-bolt icon), daily step count
  (sneaker icon — replaced the old BT-connection status field), date, and
  a compass ring with cardinal ticks.
- Heading comes from `Activity.getActivityInfo().currentHeading` (only
  populated during a tracked activity, `null`/north-up otherwise) — no
  continuous `Sensor.registerSensorDataListener`, deliberately avoided for
  battery reasons.
- Background (`resources/drawables/background.png`) is a hand-picked
  176×176 1-bit crop from `manyBg.png` (an untracked 2048×2048 spritesheet
  of bold B&W geometric art — not committed, unused by the build), chosen
  by scoring candidate crops against where each text label/icon/the
  compass ring actually renders on screen.
- Legibility fix: every `drawText` call fills a solid black background
  (not transparent), and the compass ring/ticks draw a black halo pass
  before the white stroke. Needed because the new background has large
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
  runs confirmed.
- Launcher icon is still the original placeholder (black circle, white "U").

## Next steps
1. `instinct2x` throws "Invalid device id found in the application
   manifest" on every build (pre-existing, never actually fixed) — find
   the correct device id string or drop the target.
2. `instinct2s` (156×156, no subscreen) was intentionally deferred to
   focus on Instinct 2 / Surf Edition. The 156×156 layout is still
   documented in README as a future target — revisit when ready for
   multi-device builds, including re-adding a `resources-instinct2s/`
   background sized for that screen.
3. `manyBg.png` (4.2 MB) sits untracked in `resources/drawables/`, unused
   by the build — decide whether to keep it as source reference (maybe
   move it outside `resources/` so it's unambiguously not a build input)
   or delete it.
4. Swap the placeholder launcher icon for a real asset before store
   submission (carried over from the original scaffold, still not done).
5. Optional: prototype a cheap periodic `Sensor.getInfo().heading` poll
   (once per `onUpdate`, not a continuous listener) for a livelier compass
   without the battery cost of `registerSensorDataListener` — discussed,
   not implemented.
6. Optional: split into a companion Connect IQ *app* (not a watch face)
   for live accelerometer-based wave detection — watch faces can't hold a
   continuous high-rate sensor listener the way an app context can.
7. GPS quality was removed entirely (`Position.enableLocationEvents` is
   unavailable to watch-face app types). Re-adding needs the `Positioning`
   permission and a background service — documented as a known gap in
   README, not in progress.
