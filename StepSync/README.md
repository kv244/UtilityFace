# StepSync — Garmin Step Synchronization Watch-App

StepSync is a Garmin Connect IQ `watch-app` that reads your daily step count and synchronizes it via Bluetooth Low Energy (BLE) to an external receiver (such as an Arduino UNO R4 WiFi).

Unlike standard watch faces which have strict restrictions on continuous background execution and Bluetooth communication, StepSync is a foreground app that can hold a continuous connection and perform active BLE GATT operations.

## Architecture

The system consists of two main components:
1. **BLE Central (Garmin Watch)**: Scans for the receiver, establishes a connection, reads the step count from the device's activity history, and writes the value to the receiver's step count characteristic.
2. **BLE Peripheral (Arduino UNO R4 WiFi)**: Advertises the StepSync service, listens for connections, and decodes the 32-bit step count payload to trigger serial logs and blink the onboard LED.

### GATT Profile Definitions
- **Service UUID**: `329c2dc4-7fcc-47e0-b6df-20353df6efb3`
- **Step Count Characteristic UUID**: `b0a70198-d10c-4fa6-8ef3-d64e9a8f4c1d` (Properties: Write with response, payload size: 4 bytes).
- **Data Format**: 32-bit unsigned little-endian integer (`Lang.NUMBER_FORMAT_UINT32`).

---

## Garmin App Implementation Details

The watch app is written in **Monkey C** and comprises the following files:
- **[manifest.xml](manifest.xml)**: Declares the app type (`watch-app`), targets the Garmin Instinct 2, and requests the `BluetoothLowEnergy` permission.
- **[monkey.jungle](monkey.jungle)**: Configures the compilation source and resource paths.
- **[StepSyncApp.mc](source/StepSyncApp.mc)**: Registers the GATT profile definition with the Connect IQ BLE stack at startup and delegates BLE callbacks.
- **[StepSyncBleDelegate.mc](source/StepSyncBleDelegate.mc)**: Implements the `BluetoothLowEnergy.BleDelegate` life-cycle callbacks. It handles scanning, pairing with `StepSyncArduino`, encoding steps into a `ByteArray`, and writing them to the characteristic.
- **[StepSyncView.mc](source/StepSyncView.mc)**: Renders the step count, connection status, last sync timestamp, and interaction instructions.
- **[StepSyncDelegate.mc](source/StepSyncDelegate.mc)**: Captures user input (pressing the **SELECT** button) to force a manual sync or trigger a reconnection attempt.

---

## How to Compile and Launch the Application

### Prerequisites
1. **Garmin Connect IQ SDK**: Install the SDK Manager, download SDK `9.2.0` (or similar), and pull the `instinct2` device image.
2. **Java 11+**: Make sure Java is on your system path.
3. **Developer Key**: A valid developer key is required. The build script uses the default key located at `C:\Users\julia\AppData\Roaming\Garmin\ConnectIQ\developer_key.der`.

### Build the App (Release Mode)
Run the following PowerShell script from the root workspace directory:
```powershell
$env:PATH = "C:\Program Files\Processing\app\resources\jdk\bin;$env:PATH"
$sdk = "C:\Users\julia\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin"

& "$sdk\monkeyc.bat" -l 3 -w -r -f StepSync\monkey.jungle -d instinct2 `
    -o StepSync\C2D3E4F5.PRG `
    -y "C:\Users\julia\AppData\Roaming\Garmin\ConnectIQ\developer_key.der"
```

### Launch in Simulator
To test the app locally:
1. Start the Connect IQ simulator:
   ```powershell
   Start-Process "$sdk\simulator.exe"
   ```
2. Sideload the compiled binary:
   ```powershell
   & "$sdk\monkeydo.bat" StepSync\C2D3E4F5.PRG instinct2
   ```
3. Use the simulator's **SELECT** button (Enter key) to trigger manual syncs, and change steps in **Simulation -> Activity Monitor** to test UI updates.

---

## Arduino Receiver Setup

The Arduino source code is located in `arduino/StepSyncReceiver/StepSyncReceiver.ino`.

1. Open the sketch in the **Arduino IDE**.
2. Install the **ArduinoBLE** library from the Library Manager.
3. Connect your **Arduino UNO R4 WiFi** board.
4. Upload the sketch and open the **Serial Monitor** at **115200 baud**.
5. Once active, it will start advertising as `StepSyncArduino` and wait for the Garmin watch app to connect and sync steps.
