import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Companion app to UtilityFace (see ../UtilityFace/MEMORY.md next step 6).
// Deliberately a plain App, not a WatchFace: it needs
// Sensor.registerSensorDataListener, a continuous high-rate accelerometer
// listener, which watch faces can't hold onto the way a foreground app can.
class WaveDetectorApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new WaveDetectorView();
        return [ view, new WaveDetectorDelegate(view) ];
    }

}
