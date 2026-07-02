import Toybox.WatchUi;
import Toybox.Lang;

// SELECT resets the wave count -- the only interaction this prototype needs.
class WaveDetectorDelegate extends WatchUi.BehaviorDelegate {

    private var mView as WaveDetectorView;

    function initialize(view as WaveDetectorView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        mView.resetCount();
        return true;
    }

}
