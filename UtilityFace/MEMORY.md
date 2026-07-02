# UtilityFace — Session Memory

## Target
Garmin Instinct 2 / 2S / 2X, incl. Surf Edition (same HW, surf-specific
firmware only — no separate SDK device target needed for Surf variants).

## Toolchain
Monkey C only. No C/Python/ASM path exists for Connect IQ. SDK Manager +
`monkeyc` CLI + `connectiq` simulator + `monkeydo`.

## State
- Scaffold complete: manifest, jungle, app entry, view, strings, placeholder
  drawable icon.
- `UtilityFaceView.mc` draws: time, HR, SpO2, altitude, temp, battery, GPS
  quality (one-shot, not continuous), BT status, date, compass heading tick.
- Not yet built/tested in simulator (no SDK in this environment) — needs a
  local build pass to catch API-surface issues (e.g. confirm
  `getOxygenSaturationHistory` / `getTemperatureHistory` are present on this
  device's SDK version; some SensorHistory methods are firmware-gated).

## Next steps
1. Build against real SDK, fix any `has :methodName` gating issues surfaced
   by the compiler/simulator.
2. Decide on continuous vs one-shot GPS polling trade-off once battery
   impact is measured on hardware.
3. Optional: split into a companion Connect IQ *app* (not watch face) for
   live accelerometer-based surf/wave detection — watch faces can't hold a
   continuous high-rate sensor listener the way an app context can.
4. Swap placeholder launcher icon for a real asset before store submission.
