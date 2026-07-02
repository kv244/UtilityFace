import Toybox.WatchUi;
import Toybox.Lang;

class StepSyncDelegate extends WatchUi.BehaviorDelegate {

    private var mBleDelegate as StepSyncBleDelegate?;

    function initialize(bleDelegate as StepSyncBleDelegate?) {
        BehaviorDelegate.initialize();
        mBleDelegate = bleDelegate;
    }

    // Handle SELECT button (the enter key on simulator or lower-left button on Instinct 2)
    function onSelect() as Boolean {
        var bleDelegate = mBleDelegate;
        if (bleDelegate != null) {
            // Try to sync steps. If not connected, trigger a scan restart.
            var success = bleDelegate.syncSteps();
            if (!success) {
                bleDelegate.startScanning();
            }
        }
        return true;
    }

}
