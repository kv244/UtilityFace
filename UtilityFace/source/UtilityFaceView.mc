import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;
import Toybox.Math;
import Toybox.Activity;

// WatchFace is a specialised subclass of WatchUi.View. The OS gives it a
// different lifecycle to ordinary app views: it runs continuously in the
// background, receives a low-power (1 Hz) update budget, and can opt into
// a per-second partial-redraw when the wrist is raised (high-power mode).
class UtilityFaceView extends WatchUi.WatchFace {

    private var mIsSleeping as Boolean = false;
    private var mBackground as WatchUi.BitmapResource?;

    function initialize() {
        WatchFace.initialize();
    }

    // onLayout is called once after initialize(), before the first draw.
    // Use it to load bitmap resources or measure layout constants that
    // depend on dc.getWidth()/getHeight(). Left empty here because all
    // layout is computed dynamically in onUpdate from the dc dimensions.
    function onLayout(dc as Graphics.Dc) as Void {
        mBackground = WatchUi.loadResource(Rez.Drawables.Background) as WatchUi.BitmapResource;
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
        mIsSleeping = false;
        WatchUi.requestUpdate();
    }

    // Called when the watch enters ambient mode (wrist lowered / timeout).
    // In ambient mode only onUpdate fires (once per minute); onPartialUpdate
    // is suppressed to save battery. Turn off any animations here.
    function onEnterSleep() as Void {
        mIsSleeping = true;
        WatchUi.requestUpdate();
    }

    // onUpdate is the main draw callback. In low-power (ambient) mode the OS
    // calls it once per minute. In high-power mode it is called whenever
    // WatchUi.requestUpdate() is invoked (or automatically after onExitSleep).
    // Always does a full clear + redraw of the whole screen.
    function onUpdate(dc as Graphics.Dc) as Void {
        if (mBackground != null) {
            dc.drawBitmap(0, 0, mBackground);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
        }

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var radius = (w < h ? w : h) / 2 - 4;

        var subscreen = null;
        if (WatchUi has :getSubscreen) {
            subscreen = WatchUi.getSubscreen();
        }

        if (subscreen != null) {
            var sub = subscreen as Graphics.BoundingBox;
            drawCompassRing(dc, cx, cy, radius);
            
            var cx_main = (sub.x as Number) / 2;
            drawTimeLeft(dc, cx_main);
            
            if (!mIsSleeping) {
                drawSecondsLeft(dc, cx_main);
            }
            
            drawHeartRateSubscreen(dc, sub);
            drawSpO2Left(dc, cy, w);
            
            drawAltitudeAndTemp(dc, cy, w);
            drawStatusRow(dc, cy, w);
            drawDate(dc, cx, cy);
        } else {
            drawCompassRing(dc, cx, cy, radius);
            drawTime(dc, cx, h);
            
            if (!mIsSleeping) {
                drawSeconds(dc);
            }
            
            drawHeartRate(dc, cy, w);
            drawSpO2(dc, cy, w);
            drawAltitudeAndTemp(dc, cy, w);
            drawStatusRow(dc, cy, w);
            drawDate(dc, cx, cy);
        }
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

        var x = (w / 2) + 34;
        var y = 18;

        var subscreen = null;
        if (WatchUi has :getSubscreen) {
            subscreen = WatchUi.getSubscreen();
        }

        if (subscreen != null) {
            var sub = subscreen as Graphics.BoundingBox;
            var cx_main = (sub.x as Number) / 2;
            var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
            var timeWidth = dc.getTextWidthInPixels(timeStr, Graphics.FONT_NUMBER_MEDIUM);
            x = cx_main + (timeWidth / 2) + 4;
        }

        var boxW = (subscreen != null) ? 24 : 40;
        var boxH = 20;

        // Erase just the seconds box, then redraw the new value.
        dc.setClip(x, y, boxW, boxH);
        if (mBackground != null) {
            dc.drawBitmap(0, 0, mBackground);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(x, y, boxW, boxH);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.clearClip();
    }

    // Draws seconds during a full redraw when not in sleep mode.
    private function drawSeconds(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var clock = System.getClockTime();
        var secStr = clock.sec.format("%02d");

        var x = (w / 2) + 34;
        var y = 18;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
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

        var heading = getHeading();
        var headingRad = (heading != null) ? heading : 0.0;

        // Static cardinal tick marks at N/E/S/W (degrees clockwise from north)
        var cardinalDegs = [0.0, 90.0, 180.0, 270.0] as Array<Float>;
        for (var i = 0; i < cardinalDegs.size(); i++) {
            var angle = (cardinalDegs[i] * Math.PI / 180.0) - headingRad - Math.PI / 2.0;
            var tickInner = r - 8;
            var x1 = cx + (tickInner * Math.cos(angle)).toNumber();
            var y1 = cy + (tickInner * Math.sin(angle)).toNumber();
            var x2 = cx + (r * Math.cos(angle)).toNumber();
            var y2 = cy + (r * Math.sin(angle)).toNumber();

            // Thicker tick line for North
            if (i == 0) {
                dc.setPenWidth(3);
            } else {
                dc.setPenWidth(1);
            }
            dc.drawLine(x1, y1, x2, y2);
        }
        dc.setPenWidth(1); // Restore pen width
    }

    private function getHeading() as Float? {
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null && activityInfo.currentHeading != null) {
            return activityInfo.currentHeading;
        }
        return null;
    }

    private function drawTimeLeft(dc as Graphics.Dc, cx_main as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx_main, 14, Graphics.FONT_NUMBER_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawSecondsLeft(dc as Graphics.Dc, cx_main as Number) as Void {
        var clock = System.getClockTime();
        var secStr = clock.sec.format("%02d");
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        
        var timeWidth = dc.getTextWidthInPixels(timeStr, Graphics.FONT_NUMBER_MEDIUM);
        var x = cx_main + (timeWidth / 2) + 4;
        var y = 18;
        
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawHeartRateSubscreen(dc as Graphics.Dc, subscreen as Graphics.BoundingBox) as Void {
        var cx = (subscreen.x as Number) + (subscreen.width as Number) / 2;
        var cy = (subscreen.y as Number) + (subscreen.height as Number) / 2;
        
        var hr = null;
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            hr = info.currentHeartRate;
        } else {
            var iter = ActivityMonitor.getHeartRateHistory(1, true);
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    hr = sample.heartRate;
                }
            }
        }
        
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy - 6, Graphics.FONT_SMALL, (hr != null ? hr.toString() : "--"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawSpO2Left(dc as Graphics.Dc, cy as Number, w as Number) as Void {
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
        dc.drawText(24, cy - 30, Graphics.FONT_SMALL,
            "O2 " + (spo2 != null ? (spo2 as Float).format("%.0f") + "%" : "--"), Graphics.TEXT_JUSTIFY_LEFT);
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
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            hr = info.currentHeartRate;
        } else {
            var iter = ActivityMonitor.getHeartRateHistory(1, true);
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    hr = sample.heartRate;
                }
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(24, cy - 30, Graphics.FONT_SMALL,
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
        dc.drawText(w - 24, cy - 30, Graphics.FONT_SMALL,
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
        dc.drawText(24, cy + 6, Graphics.FONT_XTINY,
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
        dc.drawText(w - 24, cy + 6, Graphics.FONT_XTINY,
            "T " + (temp != null ? temp.format("%.0f") + "C" : "--"), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // System.getSystemStats() returns device-level stats: battery (0–100 Float),
    // charging state, memory usage, etc. System.getDeviceSettings() returns
    // user/device configuration including phoneConnected (Bluetooth link state).
    // Both are cheap synchronous calls with no permission requirements.
    private function drawStatusRow(dc as Graphics.Dc, cy as Number, w as Number) as Void {
        var stats = System.getSystemStats();
        var settings = System.getDeviceSettings();
        var y = cy + 25;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(24, y, Graphics.FONT_XTINY,
            "BAT " + stats.battery.format("%d") + "%", Graphics.TEXT_JUSTIFY_LEFT);

        var btLabel = settings.phoneConnected ? "BT ON" : "BT --";
        dc.drawText(w - 24, y, Graphics.FONT_XTINY, btLabel, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Gregorian.info(moment, format) converts a Time.Moment (Unix-epoch-based
    // opaque type) into a human-readable struct with day_of_week, day, month,
    // year fields. TIME_FORMAT_MEDIUM returns localised short strings for
    // day/month names (e.g. "Wed", "Jul") rather than raw integers.
    private function drawDate(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.day, now.month]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 44, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
