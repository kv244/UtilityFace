import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.ActivityMonitor;
import Toybox.WatchUi;

class StepSyncBleDelegate extends BluetoothLowEnergy.BleDelegate {
    // The 128-bit Service and Characteristic UUIDs matching the Arduino receiver
    public const SERVICE_UUID = BluetoothLowEnergy.stringToUuid("329c2dc4-7fcc-47e0-b6df-20353df6efb3");
    public const CHAR_UUID = BluetoothLowEnergy.stringToUuid("b0a70198-d10c-4fa6-8ef3-d64e9a8f4c1d");

    public var mStatus as String = "Scanning...";
    public var mLastSyncStr as String = "Never";
    
    private var mDevice as Device? = null;
    private var mScanning as Boolean = false;

    function initialize() {
        BleDelegate.initialize();
        startScanning();
    }

    function startScanning() as Void {
        if (mScanning) {
            return;
        }
        mStatus = "Scanning...";
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        mScanning = true;
        WatchUi.requestUpdate();
    }

    function stopScanning() as Void {
        if (!mScanning) {
            return;
        }
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        mScanning = false;
    }

    // Matches on advertised name only -- deliberately not a "name, or
    // failing that, service UUID" fallback. The watch's own pairing with
    // the Garmin Connect Mobile phone app is a separate system-level BLE
    // channel that this scan wouldn't see, but a UUID-only fallback would
    // still happily pairDevice() on *any* nearby peripheral that happens
    // to advertise a matching 128-bit UUID (coincidentally or otherwise).
    // Exact name match is the only signal that's actually unambiguous.
    function onScanResults(scanResults as Iterator) as Void {
        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (result instanceof ScanResult) {
                var name = result.getDeviceName();

                if (name != null && name.equals("StepSyncArduino")) {
                    stopScanning();
                    mDevice = BluetoothLowEnergy.pairDevice(result);
                    mStatus = "Connecting...";
                    WatchUi.requestUpdate();
                    break;
                }
            }
        }
    }

    function onConnectedStateChanged(device as Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            mDevice = device;
            mStatus = "Connected";
            WatchUi.requestUpdate();
            // Automatically push the current steps to the Arduino once connected
            syncSteps();
        } else {
            mDevice = null;
            mStatus = "Disconnected";
            WatchUi.requestUpdate();
            // Restart scanning when disconnected
            startScanning();
        }
    }

    function syncSteps() as Boolean {
        if (mDevice == null) {
            mStatus = "Not connected";
            WatchUi.requestUpdate();
            return false;
        }

        var service = mDevice.getService(SERVICE_UUID);
        if (service == null) {
            mStatus = "Service not found";
            WatchUi.requestUpdate();
            return false;
        }

        var characteristic = service.getCharacteristic(CHAR_UUID);
        if (characteristic == null) {
            mStatus = "Char not found";
            WatchUi.requestUpdate();
            return false;
        }

        var info = ActivityMonitor.getInfo();
        var steps = 0;
        if (info != null && info.steps != null) {
            steps = info.steps as Number;
        }

        mStatus = "Syncing " + steps + "...";
        WatchUi.requestUpdate();

        // ByteArray.encodeNumber's :endianness option defaults to
        // Lang.ENDIAN_LITTLE per the SDK docs (Toybox.Lang.ByteArray), so
        // this was already correct -- made explicit since the Arduino
        // receiver's byte order is a wire-format contract worth not
        // depending on an implicit SDK default for.
        var bytes = [0, 0, 0, 0]b;
        bytes = bytes.encodeNumber(steps, Lang.NUMBER_FORMAT_UINT32, {:endianness => Lang.ENDIAN_LITTLE});

        try {
            characteristic.requestWrite(bytes, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
            return true;
        } catch (e) {
            mStatus = "Write error";
            WatchUi.requestUpdate();
            return false;
        }
    }

    function onCharacteristicWrite(characteristic as Characteristic, status as Status) as Void {
        if (characteristic.getUuid().equals(CHAR_UUID)) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
                mStatus = "Synced!";
                var clockTime = System.getClockTime();
                if (clockTime != null) {
                    mLastSyncStr = clockTime.hour.format("%02d") + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
                }
            } else {
                mStatus = "Sync Error: " + status;
            }
            WatchUi.requestUpdate();
        }
    }
}
