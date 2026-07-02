# Reverse Engineering a PRG

`prg_inspect.py` is a structural parser for Garmin Connect IQ `.PRG` files —
the compiled output of the Monkey C toolchain. This document explains how it
works, what "decompiling" a `.PRG` means in practice, and walks through a
real decompile of this project's own binary.

## Background

A `.PRG` is a flat sequence of TLV (type-length-value) sections: a 4-byte
big-endian tag, a 4-byte big-endian length, then the payload. Section tags
and layouts aren't officially documented by Garmin, but they've been
reverse-engineered publicly — `prg_inspect.py` implements the container
format as described by [pzl/ciqdb](https://github.com/pzl/ciqdb) and
corroborated by Anvil Secure's and Atredis Partners' Garmin VM research (see
sources at the bottom).

Sections relevant to reading a `.PRG`:

| Tag | Section | Contents |
|---|---|---|
| `0xd000d000` | Head | CIQ API version, background offsets, trial flag |
| `0x6060c0de` | Entry Points | app UUID, app type, label/entry/module symbol IDs |
| `0xda7ababe` | Data | class field definitions + a string-literal pool |
| `0xc0debabe` | Code | the actual Monkey C VM bytecode |
| `0xc0de7ab1` | Code Table | PC → source line mapping |
| `0xc1a557b1` | Class Table | imported module/class references |
| `0xf00d600d` | Resources | compiled fonts/bitmaps/layouts |
| `0x6000db01` | Permissions | declared `iq:uses-permission` entries |
| `0x0ece7105` | Exceptions | try/catch PC ranges |
| `0x5717b015` | **Symbols** | id → name table (**only present in debug/dev builds**) |
| `0x5e771465` | Settings | app property definitions + defaults |
| `0xe1c0de12` | Developer Signature | RSA sig + modulus + exponent |

## What "decompiling" means here

`prg_inspect.py` does **not** disassemble the Code section into Monkey C VM
opcodes/mnemonics — the exact numeric opcode encoding for the ~53–55
instructions isn't reliably published, and guessing would produce
plausible-looking but wrong output. What it *does* do, which already
recovers most of the useful information in practice:

1. Walk every top-level section and report offsets/sizes.
2. Parse Head, Entry Points, Permissions, Settings, and the Data section's
   class definitions structurally.
3. If a **Symbols** section is present (debug/dev builds only — see below),
   resolve every numeric ID referenced elsewhere in the file back to its
   original Monkey C identifier: class names, method names, module imports,
   permission names, everything.
4. Independently of the Symbols section, scan the Data section for the
   `0x01 <u16 length> <bytes>` string-literal encoding to recover every
   string constant embedded in the app (URLs, format strings, UI copy),
   which works even on stripped release binaries.

That combination — symbol resolution plus literal recovery — is enough to
tell you what an app talks to, what it stores, and how it's structured,
without reconstructing control flow.

## Debug builds vs. release builds

The Symbols section only exists if the app wasn't compiled with `-r`
(`--release`, "strip debug information"). This project's documented build
command (see [README.md](README.md)) does **not** pass `-r`, so
`A1B2C3D4.PRG` is a dev build and ships a full Symbols section — 2,981
entries, ~84 KB, more than the Code section itself. Rebuilding the identical
source with `-r` added:

```
                      dev build (no -r)   release build (-r)
Total size            105,884 bytes       17,804 bytes
Data section           1,654 bytes           674 bytes
Symbols section        83,671 bytes        (absent)
```

The size difference is almost entirely the Symbols section. This is also
why `E6672407.PRG` (a real Store-distributed third-party app analyzed
separately — see the file's git history) had no Symbols section: Store
builds are release builds.

**Practical note**: the dev build's Data-section string pool also leaks the
full local filesystem paths of every source file compiled in (see the
`.mc`/`.mcgen` paths in the walkthrough below). If you ever distribute a
`.PRG` built without `-r`, you're shipping your local username and directory
layout inside it.

## Walkthrough: decompiling `A1B2C3D4.PRG`

```
python prg_inspect.py UtilityFace/A1B2C3D4.PRG
```

**Section layout** (105,884 bytes total, fully accounted for):

```
0xd000d000  Head                          33 bytes
0x6060c0de  EntryPoints                   38 bytes
0xda7ababe  Data                        1654 bytes
0xc0debabe  Code                        4233 bytes
0xc0de7ab1  CodeTable (PC->line)        3346 bytes
0xc1a557b1  ClassTable (imports)        2394 bytes
0xf00d600d  Resources                   8863 bytes
0x6000db01  Permissions                    6 bytes
0x0ece7105  Exceptions                     2 bytes
0x5717b015  Symbols                    83671 bytes
0x5e771465  Settings                       0 bytes
0xe1c0de12  DeveloperSignature          1540 bytes
0x00000000  End                            0 bytes
```

**Head**: `{'ciq_api_version': '6.0.2', 'app_trial_enabled': False}`

**Entry point** (fully resolved via the Symbols section):

```
uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890
type: WatchFace
label_symbol:  AppName
entry_symbol:  UtilityFaceApp
module_symbol: globals
```

**Declared permissions**: `['Toybox_SensorHistory']` — matches the single
`<iq:uses-permission id="SensorHistory" />` in `manifest.xml`.

**App-local symbols** (the low, non-API-namespace IDs are the app's own
classes/methods, in this build's exact source form):

```
   5: UtilityFaceApp
   6: UtilityFaceView
   7: <globals/UtilityFaceView/<>drawAltitudeAndTemp>
   8: <globals/UtilityFaceView/<>drawCompassRing>
   9: <globals/UtilityFaceView/<>drawDate>
  10: <globals/UtilityFaceView/<>drawHeartRate>
  11: <globals/UtilityFaceView/<>drawHeartRateSubscreen>
  12: <globals/UtilityFaceView/<>drawSeconds>
  13: <globals/UtilityFaceView/<>drawSecondsLeft>
  14: <globals/UtilityFaceView/<>drawSpO2>
  15: <globals/UtilityFaceView/<>drawSpO2Left>
  16: <globals/UtilityFaceView/<>drawStatusRow>
  17: <globals/UtilityFaceView/<>drawTime>
  18: <globals/UtilityFaceView/<>drawTimeLeft>
  19: <globals/UtilityFaceView/<>getHeading>
  20: <globals/UtilityFaceView/<>mBackground>
  21: <globals/UtilityFaceView/<>mIsSleeping>
  22: LauncherIcon
  23: AppName
```

That alone reconstructs the whole view's method surface — draw routines for
altitude/temp, compass ring, date, heart rate (main + subscreen), seconds
(main + left variant), SpO2 (main + left variant), status row, time (main +
left variant), plus a heading helper and two fields (`mBackground`,
`mIsSleeping`) — without reading a line of source. (IDs above 8,388,608 /
`0x800000` in the full table are Toybox/firmware API symbols pulled in by
`import` statements, not app code — 2,958 of the 2,981 total entries.)

**Recovered string literals** (Data section, format-string / UI-copy pool):

```
'$1$ $2$ $3$'                                              format template
'$1$:$2$'                                                   format template
'%.0f'  '%02d'  '%d'                                        printf-style formats
'--'                                                         placeholder text
'ALT '  'BAT '  'BT --'  'BT ON'  'HR '  'HR'  'O2 '  'T '   on-screen labels
'onEnterSleep' 'onExitSleep' 'onLayout' 'onPartialUpdate'
'onShow' 'onStart' 'onStop' 'onUpdate' 'initialize'          lifecycle method names
'getApp' 'getInitialView'                                    App entry hooks
C:\Users\julia\Documents\UtilityFace\UtilityFace\source\UtilityFaceApp.mc
C:\Users\julia\Documents\UtilityFace\UtilityFace\source\UtilityFaceView.mc
C:\Users\julia\Documents\UtilityFace\UtilityFace\gen\006-B3888-00\source\Rez.mcgen
```

The last three lines are the local absolute source paths mentioned above —
recovered with zero symbol-table dependency, purely from the string-literal
scan, which is exactly the technique that pulled the vendor URLs and
subscription/trial strings out of the unrelated stripped `E6672407.PRG`
binary in the earlier analysis.

## Usage

```
python prg_inspect.py <path-to.prg>
```

Prints the section layout, Head, Entry Points, Permissions, Settings, the
full symbol table (if present), and every recovered Data-section string
literal.

## Sources

- [pzl/ciqdb — Connect IQ (PRG) parser and debugger](https://github.com/pzl/ciqdb)
- [Compromising Garmin's Sport Watches: A Deep Dive into GarminOS and its MonkeyC Virtual Machine — Anvil Secure](https://www.anvilsecure.com/blog/compromising-garmins-sport-watches-a-deep-dive-into-garminos-and-its-monkeyc-virtual-machine.html)
- [A Watch, a Virtual Machine, and Broken Abstractions — Atredis Partners](https://www.atredis.com/blog/2020/11/4/garmin-forerunner-235-dion-blazakis)
- [Reverse Engineering Garmin Watch Applications with Ghidra — Anvil Secure](https://www.anvilsecure.com/blog/reverse-engineering-garmin-watch-applications-with-ghidra.html)
