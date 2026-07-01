# UtilityFace — Instinct 2 Sensor Dashboard Watch Face

Quadrant-layout watch face for Garmin Instinct 2S / 2 / 2X (Surf Edition
included, same hardware). Displays time, HR, SpO2, altitude, ambient temp,
battery, BT status, static compass ring, and date in fixed screen positions —
no menu diving.

![Watch face running in simulator](output-emulator.png)

## Layout (156×156 instinct2s)

```
        |  (N tick)  |
HR 80        20:11        O2 95%
             :ss
        |           |
    ALT 1372m     T 21C
    BAT 50%       BT ON
         Wed 1 Jul
        |  (S tick)  |
```

## Hardware — Instinct 2S (Surf Edition)

| | |
|---|---|
| **CPU** | ARM Cortex-M4F @ ~200 MHz (exact clock not published by Garmin) |
| **Flash** | 32 MB (firmware + apps + data share this) |
| **RAM** | ~256 KB available to Connect IQ apps (heap-managed by the Monkey C runtime) |
| **Display** | 156×156 px, monochrome MIP (Memory-in-Pixel), always-on, sunlight-readable |
| **Sensors** | Barometric altimeter, 3-axis compass, wrist HR (Elevate v4), pulse-ox (SpO2), thermometer, accelerometer |
| **GPS** | Multi-band (L1/L5) with SatIQ; typical first fix ~30 s cold, <5 s warm |
| **Battery** | ~40 h GPS mode, ~28 days watch mode (per Garmin spec) |

**Runtime memory budget for this face (estimated):**

The Connect IQ VM reserves a fixed heap per app. For watch faces on the
Instinct 2 family the limit is ~256 KB. Rough breakdown for UtilityFace:

- VM + runtime overhead: ~80 KB
- Compiled bytecode (`.prg`): ~12 KB
- String/font data loaded at runtime: ~20 KB
- Stack + local variables per `onUpdate` call: <1 KB
- **Total estimated peak: ~115 KB** — comfortably inside the 256 KB limit,
  leaving headroom for adding steps, stress, or body battery fields.

`System.getSystemStats().usedMemory` / `.totalMemory` report live figures at
runtime; call these in `onUpdate` and `dc.drawText` them temporarily to
profile your own builds.

## Toolchain

Garmin Connect IQ apps compile from **Monkey C** only. The SDK ships:

- `monkeyc` — compiler (CLI, scriptable — fits a PowerShell/CI pipeline)
- `simulator.exe` — runs the compiled `.prg` without a physical watch
- `monkeydo` — sideloads a build into the running simulator from CLI

Requires **Java 11+** on PATH. If not installed system-wide, prepend the JDK
bin dir before calling the SDK bat files (e.g. the JDK bundled with Processing
at `C:\Program Files\Processing\app\resources\jdk\bin` works fine).

## Setup

1. Install the Connect IQ SDK Manager from Garmin's developer site; pull the
   SDK and at least the `instinct2s` device image through it.
2. Generate a developer signing key (required for every build, including
   local simulator runs):
   ```powershell
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER `
       -in developer_key.pem -out developer_key.der -nocrypt
   ```
   Store `developer_key.der` somewhere permanent — losing it means you cannot
   update a previously published app.
3. VS Code + the **Monkey C** extension adds syntax highlighting and export
   tasks. `Run Current Application` requires the extension to manage the
   simulator launch itself; use the CLI workflow below if that option is absent.

## Build (CLI)

```powershell
$env:PATH = "C:\Program Files\Processing\app\resources\jdk\bin;$env:PATH"
$sdk = "C:\Users\julia\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin"

& "$sdk\monkeyc.bat" -l 3 -w -f monkey.jungle -d instinct2s `
    -o utilityface.prg `
    -y "C:\Users\julia\AppData\Roaming\Garmin\ConnectIQ\developer_key.der"
```

Flags: `-l 3` = strict type check, `-w` = show warnings.

## Run in simulator (CLI)

```powershell
Start-Process "$sdk\simulator.exe"
Start-Sleep -Seconds 5
& "$sdk\monkeydo.bat" utilityface.prg instinct2s
```

## Deploy to hardware

Copy `utilityface.prg` to `GARMIN\Apps\` on the watch when connected via USB
(mass storage mode), or push via Garmin Express / Connect Mobile if signed for
distribution.

## Permissions

- `SensorHistory` — HR, SpO2, elevation, temperature (last logged sample)

## Known gaps / next steps

- **Compass heading**: The ring shows static N/E/S/W tick marks only. Live
  heading via `Sensor.getInfo().heading` requires the `Sensor` permission,
  which in turn requires `Background` for watch face apps — adding `Background`
  without proper `(:background)` annotations causes the compiler to treat the
  entire app as a background process (no Graphics API access). Fix: add a
  proper background service entry point annotated with `(:background)` and
  keep the UI code annotated with `(:foreground)`.
- **GPS quality**: Removed (`Position.enableLocationEvents` is unavailable to
  watch face app types). Re-adding requires the `Positioning` permission and
  routing through a background service.
- **Launcher icon**: Placeholder scaled from 40×40; device expects 54×54.
  Replace `resources/drawables/launcher_icon.png` with a 54×54 PNG before
  publishing to the Connect IQ store.
- **Accelerometer/gyro**: Not in `SensorHistory` at watch-face refresh rates.
  Continuous sampling needs `Sensor.registerSensorDataListener`, which belongs
  in an activity app context (e.g. a wave-detection app).
- **Device variants**: Only `instinct2s` device image is currently downloaded.
  Pull `instinct2` and `instinct2x` via SDK Manager to enable multi-target
  builds and simulator testing for those variants.
