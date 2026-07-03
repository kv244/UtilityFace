import Toybox.Background;
import Toybox.System;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Application;

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

        // Timestamp captured here (not in onBackgroundData) so it reflects
        // when the sensor was actually read, not whenever the foreground
        // app happens to notice -- onBackgroundData can be delayed if the
        // watch face isn't active when this background slice finishes.
        var clock = System.getClockTime();
        // String keys, not Symbols: Background.exit()'s docs whitelist
        // String/Number/Float/Boolean/Char/Long/Double/Array/Dictionary for
        // the data it carries across the background/foreground boundary --
        // Symbol isn't on that list. Symbol keys type-check fine (Symbol is
        // a valid Application.PropertyKeyType) but crash at runtime here
        // with "Unexpected Type Error: Failed invoking <symbol>" right at
        // this Background.exit() call -- confirmed by bisecting against a
        // debug build with logging, not guessed.
        var payload = {
            "heading" => heading,
            "hour" => clock.hour,
            "minute" => clock.min,
        } as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>;
        Background.exit(payload);
    }
}
