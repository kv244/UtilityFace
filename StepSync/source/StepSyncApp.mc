import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.BluetoothLowEnergy;

class StepSyncApp extends Application.AppBase {

    private var mBleDelegate as StepSyncBleDelegate?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        mBleDelegate = new StepSyncBleDelegate();
        BluetoothLowEnergy.setDelegate(mBleDelegate);

        // Define and register the GATT profile with Connect IQ BLE stack
        var profileDef = {
            :uuid => mBleDelegate.SERVICE_UUID,
            :characteristics => [{
                :uuid => mBleDelegate.CHAR_UUID,
                :descriptors => []
            }]
        };
        BluetoothLowEnergy.registerProfile(profileDef);
    }

    function onStop(state as Dictionary?) as Void {
        if (mBleDelegate != null) {
            mBleDelegate.stopScanning();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new StepSyncView(mBleDelegate);
        var delegate = new StepSyncDelegate(mBleDelegate);
        return [ view, delegate ];
    }

}
