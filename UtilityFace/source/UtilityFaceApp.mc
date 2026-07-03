import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Background;
import Toybox.System;
import Toybox.Time;

// AppBase is the root of every Connect IQ application. The OS instantiates
// this class once at launch and keeps it alive for the app's lifetime.
// For a watch face this means: from the moment the face is selected in
// Settings until the user switches to a different face.
//
// (:background) on the whole class (not just getServiceDelegate) is
// required once the app has any background code — the OS also
// instantiates this class in the restricted background slice to call
// getServiceDelegate() on it. Confirmed against a working reference
// (Garmin forum thread on getServiceDelegate array-return gotchas);
// annotating only the one method left the class in an inconsistent
// state and broke Graphics/WatchUi typechecking everywhere.
(:background)
class UtilityFaceApp extends Application.AppBase {

    // Called by the OS before anything else. Always delegate to
    // AppBase.initialize() first — it wires up the Toybox runtime internals.
    function initialize() {
        AppBase.initialize();
    }

    // Called after initialize() when the app is fully started.
    // 'state' carries restore data if the app was previously suspended
    // (e.g. a phone notification temporarily took over the screen); it is
    // null on a cold start. Use it to reload any cached state you saved in
    // onStop(), same pattern as Android's onRestoreInstanceState.
    //
    // Also (re-)registers the background wake used for HeadingServiceDelegate
    // -- see that file for why this exists instead of a plain
    // Sensor.getInfo() call in onUpdate. Garmin throttles the wake interval
    // to a several-minute minimum regardless of what's requested here, so
    // this is a slow drift-corrected heading refresh, not a live compass.
    function onStart(state as Dictionary?) as Void {
        if (Background.getTemporalEventRegisteredTime() == null) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
    }

    // Called when the app is about to be stopped — either because the user
    // changed watch faces, powered off, or the OS reclaimed memory.
    // Save anything you want to survive a restart into 'state' here
    // (e.g. Application.Storage for persistent prefs, or the Dictionary
    // passed back into onStart next time).
    function onStop(state as Dictionary?) as Void {
    }

    // The OS calls this once to get the first screen to display.
    // Return an Array with one View, or a View + InputDelegate pair if the
    // app needs button input. For a watch face the View is all you need —
    // button handling in faces is limited to the onKeyEvent callback anyway.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new UtilityFaceView() ];
    }

    // Told the OS this app has background code via the Background manifest
    // permission; this is what actually gets invoked in the restricted
    // background slice.
    function getServiceDelegate() as Array {
        return [ new HeadingServiceDelegate() ];
    }

    // Called once the background slice finishes and calls
    // Background.exit(data). 'data' is the {"heading", "hour", "minute"}
    // dictionary HeadingServiceDelegate.onTemporalEvent() built (String
    // keys, not Symbols -- see the comment there). Just persist it; no
    // WatchUi call here (this method is typechecked against the background
    // slice too, where WatchUi isn't available) -- the next regular
    // onUpdate (at most a minute away) picks up the new values.
    function onBackgroundData(data) as Void {
        // Application.PersistableType and Storage.ValueType are separate
        // (overlapping) union types under strict typecheck, hence the casts.
        var result = data as Dictionary;
        Storage.setValue("backgroundHeading", result["heading"] as Storage.ValueType);
        Storage.setValue("backgroundHeadingHour", result["hour"] as Storage.ValueType);
        Storage.setValue("backgroundHeadingMinute", result["minute"] as Storage.ValueType);
    }

}

// Module-level helper so any source file can call getApp() to reach the
// singleton AppBase instance without importing a global. Equivalent to a
// typed Application.getApp() cast — saves repeating the cast everywhere.
function getApp() as UtilityFaceApp {
    return Application.getApp() as UtilityFaceApp;
}
