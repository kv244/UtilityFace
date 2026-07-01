import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;
import Toybox.Math;

// WatchFace is a specialised subclass of WatchUi.View. The OS gives it a
// different lifecycle to ordinary app views: it runs continuously in the
// background, receives a low-power (1 Hz) update budget, and can opt into
// a per-second partial-redraw when the wrist is raised (high-power mode).
class UtilityFaceView extends WatchUi.WatchFace {

    function initialize() {
        WatchFace.initialize();
    }

    // onLayout is called once after initialize(), before the first draw.
    // Use it to load bitmap resources or measure layout constants that
    // depend on dc.getWidth()/getHeight(). Left empty here because all
    // layout is computed dynamically in onUpdate from the dc dimensions.
    function onLayout(dc as Graphics.Dc) as Void {
    }

    // onShow fires every time this face becomes visible — on cold start and
    // whenever it returns to the foreground (e.g. after a notification overlay
    // dismisses). A good place to re-arm one-shot listeners or reset state
    // that should be fresh each time the face appears.
    function onShow() as Void {
    }

    // Called by the OS when the watch exits ambient (low-power) mode and the
    // user is actively looking at the face. High-power mode enables
    // onPartialUpdate (per-second redraws) and faster sensor polling.
    function onExitSleep() as Void {
    }

    // Called when the watch enters ambient mode (wrist lowered / timeout).
    // In ambient mode only onUpdate fires (once per minute); onPartialUpdate
    // is suppressed to save battery. Turn off any animations here.
    function onEnterSleep() as Void {
    }

    // onUpdate is the main draw callback. In low-power (ambient) mode the OS
    // calls it once per minute. In high-power mode it is called whenever
    // WatchUi.requestUpdate() is invoked (or automatically after onExitSleep).
    // Always does a full clear + redraw of the whole screen.
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var radius = (w < h ? w : h) / 2 - 4;

        drawCompassRing(dc, cx, cy, radius);
        drawTime(dc, cx, h);
        drawHeartRate(dc, cy, w);
        drawSpO2(dc, cy, w);
        drawAltitudeAndTemp(dc, cy, w);
        drawStatusRow(dc, w, h);
        drawDate(dc, cx, h);
    }

    // onPartialUpdate fires once per second while in high-power mode.
    // The key rule: only repaint the region you clip to — the rest of the
    // screen is preserved from the last onUpdate. Clipping is done with
    // dc.setClip() / dc.clearClip(). This keeps CPU time low enough to
    // avoid the watchdog that kills faces exceeding their time budget.
    // Here we use it to refresh only the seconds digits.
    function onPartialUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var clock = System.getClockTime();
        var secStr = clock.sec.format("%02d");

        var boxW = 40;
        var boxH = 20;
        var x = (w / 2) + 34;
        var y = 18;

        // Erase just the seconds box, then redraw the new value.
        dc.setClip(x, y, boxW, boxH);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(x, y, boxW, boxH);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.clearClip();
    }

    // --- Drawing helpers -----------------------------------------------

    // Draws the outer bezel circle and four cardinal tick marks (N/E/S/W).
    // dc.drawCircle(cx, cy, r) draws a circle outline — there is no filled
    // arc shorthand, so compass needles must be computed with sin/cos.
    // Live heading via Sensor.getInfo().heading requires the Sensor +
    // Background permissions and foreground/background annotations — see
    // README "Known gaps" for the upgrade path.
    private function drawCompassRing(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, r);

        // Static cardinal tick marks at N/E/S/W (degrees clockwise from north)
        var cardinalDegs = [0.0, 90.0, 180.0, 270.0] as Array<Float>;
        for (var i = 0; i < cardinalDegs.size(); i++) {
            // Convert compass bearing to screen angle: 0° (north) = top of
            // screen = -π/2 in standard screen coordinates.
            var angle = cardinalDegs[i] * Math.PI / 180.0 - Math.PI / 2.0;
            var tickInner = r - 8;
            var x1 = cx + (tickInner * Math.cos(angle)).toNumber();
            var y1 = cy + (tickInner * Math.sin(angle)).toNumber();
            var x2 = cx + (r * Math.cos(angle)).toNumber();
            var y2 = cy + (r * Math.sin(angle)).toNumber();
            dc.drawLine(x1, y1, x2, y2);
        }
    }

    // System.getClockTime() returns a ClockTime struct (hour, min, sec).
    // Lang.format() is Monkey C's printf equivalent — $1$, $2$ are
    // positional placeholders. format("%02d") zero-pads to two digits.
    // FONT_NUMBER_MEDIUM is a large digit-optimised font included in the SDK;
    // it renders more cleanly than a scaled general font for numeric displays.
    private function drawTime(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 14, Graphics.FONT_NUMBER_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ActivityMonitor.getHeartRateHistory(n, newestFirst) returns an iterator
    // over the last n logged HR samples. Calling .next() gives the most recent
    // HeartRateSample, which has a .heartRate field (beats/min) or the sentinel
    // INVALID_HR_SAMPLE when the sensor has no valid reading.
    // This is a history pull (last logged value), not a live stream —
    // the update rate matches the watch's background HR logging interval.
    private function drawHeartRate(dc as Graphics.Dc, cy as Number, w as Number) as Void {
        var hr = null;
        var iter = ActivityMonitor.getHeartRateHistory(1, true);
        if (iter != null) {
            var sample = iter.next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(18, cy - 30, Graphics.FONT_SMALL,
            "HR " + (hr != null ? hr.toString() : "--"), Graphics.TEXT_JUSTIFY_LEFT);
    }

    // SensorHistory provides time-series access to sensor logs stored by the
    // watch firmware. Each getXHistory({}) call returns an iterator ordered
    // newest-first. The empty Dictionary {} uses default options (no time
    // range filter). The 'has' guard makes the call safe across SDK versions
    // and device families that may not support the API — the compiler removes
    // the guard at build time when targeting a device that always has it.
    private function drawSpO2(dc as Graphics.Dc, cy as Number, w as Number) as Void {
        var spo2 = null;
        if (Toybox has :SensorHistory && SensorHistory has :getOxygenSaturationHistory) {
            var iter = SensorHistory.getOxygenSaturationHistory({});
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    spo2 = sample.data;
                }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // sample.data is a Float — format with "%.0f" to strip the decimal
        // places before appending the unit string.
        dc.drawText(w - 18, cy - 30, Graphics.FONT_SMALL,
            "O2 " + (spo2 != null ? (spo2 as Float).format("%.0f") + "%" : "--"), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // SensorHistory.getElevationHistory and getTemperatureHistory follow the
    // same iterator pattern as SpO2 above. Elevation is in metres (Float),
    // temperature in degrees Celsius (Float). Both are firmware-logged at
    // intervals set by the device, not on every onUpdate call.
    // The 'has' check is especially important for temperature — older SDK
    // versions and some device families omit getTemperatureHistory entirely.
    private function drawAltitudeAndTemp(dc as Graphics.Dc, cy as Number, w as Number) as Void {
        var alt = null;
        if (SensorHistory has :getElevationHistory) {
            var iter = SensorHistory.getElevationHistory({});
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    alt = sample.data;
                }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(18, cy + 12, Graphics.FONT_XTINY,
            "ALT " + (alt != null ? alt.format("%.0f") + "m" : "--"), Graphics.TEXT_JUSTIFY_LEFT);

        var temp = null;
        if (SensorHistory has :getTemperatureHistory) {
            var iter2 = SensorHistory.getTemperatureHistory({});
            if (iter2 != null) {
                var sample = iter2.next();
                if (sample != null && sample.data != null) {
                    temp = sample.data;
                }
            }
        }
        dc.drawText(w - 18, cy + 12, Graphics.FONT_XTINY,
            "T " + (temp != null ? temp.format("%.0f") + "C" : "--"), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // System.getSystemStats() returns device-level stats: battery (0–100 Float),
    // charging state, memory usage, etc. System.getDeviceSettings() returns
    // user/device configuration including phoneConnected (Bluetooth link state).
    // Both are cheap synchronous calls with no permission requirements.
    private function drawStatusRow(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var stats = System.getSystemStats();
        var settings = System.getDeviceSettings();
        var y = h - 44;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(18, y, Graphics.FONT_XTINY,
            "BAT " + stats.battery.format("%d") + "%", Graphics.TEXT_JUSTIFY_LEFT);

        var btLabel = settings.phoneConnected ? "BT ON" : "BT --";
        dc.drawText(w - 18, y, Graphics.FONT_XTINY, btLabel, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Gregorian.info(moment, format) converts a Time.Moment (Unix-epoch-based
    // opaque type) into a human-readable struct with day_of_week, day, month,
    // year fields. TIME_FORMAT_MEDIUM returns localised short strings for
    // day/month names (e.g. "Wed", "Jul") rather than raw integers.
    private function drawDate(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.day, now.month]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 26, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
