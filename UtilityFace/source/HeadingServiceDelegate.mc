import Toybox.Background;
import Toybox.System;
import Toybox.Lang;
import Toybox.Sensor;

// Runs in the OS's restricted background execution slice -- no Graphics/
// WatchUi available here, which is why this is a separate (:background)
// -annotated class rather than a method on the view. The OS wakes this up
// on the schedule requested by Background.registerForTemporalEvent() in
// UtilityFaceApp (Garmin enforces a several-minute minimum interval, so
// this is a slow drift-corrected heading, not a live compass).
(:background)
class HeadingServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var heading = null;
        if (Toybox has :Sensor) {
            var info = Sensor.getInfo();
            if (info != null && info.heading != null) {
                heading = info.heading;
            }
        }
        Background.exit(heading);
    }
}
