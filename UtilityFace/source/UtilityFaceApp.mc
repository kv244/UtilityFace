import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// AppBase is the root of every Connect IQ application. The OS instantiates
// this class once at launch and keeps it alive for the app's lifetime.
// For a watch face this means: from the moment the face is selected in
// Settings until the user switches to a different face.
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
    function onStart(state as Dictionary?) as Void {
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

}

// Module-level helper so any source file can call getApp() to reach the
// singleton AppBase instance without importing a global. Equivalent to a
// typed Application.getApp() cast — saves repeating the cast everywhere.
function getApp() as UtilityFaceApp {
    return Application.getApp() as UtilityFaceApp;
}
