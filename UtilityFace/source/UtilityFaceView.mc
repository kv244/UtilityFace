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
import Toybox.Application.Storage;

// WatchFace is a specialised subclass of WatchUi.View. The OS gives it a
// different lifecycle to ordinary app views: it runs continuously in the
// background, receives a low-power (1 Hz) update budget, and can opt into
// a per-second partial-redraw when the wrist is raised (high-power mode).
//
// disableBackgroundCheck: UtilityFaceApp is (:background)-annotated (it has
// to be, to support HeadingServiceDelegate), which makes strict typecheck
// validate everything reachable from it -- including this view, via
// getInitialView() -- against the restricted background scope, where
// Graphics/WatchUi APIs don't exist. This view is never actually
// instantiated in that scope in practice, so disable that specific check
// rather than the whole app's strict typecheck.
(:typecheck(disableBackgroundCheck))
class UtilityFaceView extends WatchUi.WatchFace {

    private var mIsSleeping as Boolean = false;
    // One pre-rotated background per hour (15 degrees apart, 360/24 -- see
    // drawables.xml). Real-time bitmap rotation (Dc.drawBitmap2 with a
    // Graphics.AffineTransform) looked like the obvious approach, but it
    // throws a runtime "Symbol Not Found" crash on this device/SDK despite
    // being in the general API docs and passing a `has` guard at compile
    // time -- confirmed by actually crashing the simulator, not assumed.
    // Swapping between 24 pre-rendered bitmaps sidesteps that, but loading
    // all 24 into memory at once in onLayout throws Out Of Memory (also
    // confirmed by crashing, not assumed) -- ~256KB heap budget doesn't
    // stretch to 24 resident decoded bitmaps. Only the current hour's
    // bitmap is kept loaded; loadBackgroundForHour swaps it out lazily.
    private var mBackground as WatchUi.BitmapResource?;
    private var mBackgroundHour as Number = -1;
    private var mBackgroundIds as Array<ResourceId> = [
        Rez.Drawables.BackgroundH00, Rez.Drawables.BackgroundH01, Rez.Drawables.BackgroundH02,
        Rez.Drawables.BackgroundH03, Rez.Drawables.BackgroundH04, Rez.Drawables.BackgroundH05,
        Rez.Drawables.BackgroundH06, Rez.Drawables.BackgroundH07, Rez.Drawables.BackgroundH08,
        Rez.Drawables.BackgroundH09, Rez.Drawables.BackgroundH10, Rez.Drawables.BackgroundH11,
        Rez.Drawables.BackgroundH12, Rez.Drawables.BackgroundH13, Rez.Drawables.BackgroundH14,
        Rez.Drawables.BackgroundH15, Rez.Drawables.BackgroundH16, Rez.Drawables.BackgroundH17,
        Rez.Drawables.BackgroundH18, Rez.Drawables.BackgroundH19, Rez.Drawables.BackgroundH20,
        Rez.Drawables.BackgroundH21, Rez.Drawables.BackgroundH22, Rez.Drawables.BackgroundH23,
    ];
    private var mIconAltitude as WatchUi.BitmapResource?;
    private var mIconTemperature as WatchUi.BitmapResource?;
    private var mIconSteps as WatchUi.BitmapResource?;
    private var mIconBattery as WatchUi.BitmapResource?;
    private var mIconSyncTime as WatchUi.BitmapResource?;

    function initialize() {
        WatchFace.initialize();
    }

    // onLayout is called once after initialize(), before the first draw.
    // Use it to load bitmap resources or measure layout constants that
    // depend on dc.getWidth()/getHeight(). Status-row labels are drawn as
    // small icons (see drawables.xml) instead of text prefixes.
    function onLayout(dc as Graphics.Dc) as Void {
        loadBackgroundForHour(System.getClockTime().hour);

        mIconAltitude = WatchUi.loadResource(Rez.Drawables.IconAltitude) as WatchUi.BitmapResource;
        mIconTemperature = WatchUi.loadResource(Rez.Drawables.IconTemperature) as WatchUi.BitmapResource;
        mIconSteps = WatchUi.loadResource(Rez.Drawables.IconSteps) as WatchUi.BitmapResource;
        mIconBattery = WatchUi.loadResource(Rez.Drawables.IconBattery) as WatchUi.BitmapResource;
        mIconSyncTime = WatchUi.loadResource(Rez.Drawables.IconSyncTime) as WatchUi.BitmapResource;
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
        drawBackground(dc);

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var radius = (w < h ? w : h) / 2 - 4;

        var subscreen = null;
        if (WatchUi has :getSubscreen) {
            subscreen = WatchUi.getSubscreen();
        }

        // drawCompassRing goes last in both branches: every text draw now
        // paints an opaque black background (see drawIconValueLeft/Right),
        // so anything drawn after the ring would erase whatever ring/tick
        // pixels its background rectangle happens to cover. Drawing the
        // ring last means nothing can paint over it, at the cost of the
        // ring's own black-halo strokes potentially covering the outer
        // edge of a text box if one ever reaches that far out (none do at
        // the current 24px margins).
        if (subscreen != null) {
            var sub = subscreen as Graphics.BoundingBox;
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
            drawCompassRing(dc, cx, cy, radius);
        } else {
            drawTime(dc, cx, h);

            if (!mIsSleeping) {
                drawSeconds(dc);
            }

            drawHeartRate(dc, cy, w);
            drawSpO2(dc, cy, w);
            drawAltitudeAndTemp(dc, cy, w);
            drawStatusRow(dc, cy, w);
            drawDate(dc, cx, cy);
            drawCompassRing(dc, cx, cy, radius);
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

        // Erase just the seconds box, then redraw the new value. Must use
        // the same rotated draw as onUpdate, or this patch shows a
        // stale unrotated fragment of the background underneath the digits.
        dc.setClip(x, y, boxW, boxH);
        drawBackground(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Drawing helpers -----------------------------------------------

    // Picks the pre-rotated background matching the current hour and draws
    // it plainly -- see mBackgrounds declaration for why this isn't done
    // via a runtime rotation transform.
    private function drawBackground(dc as Graphics.Dc) as Void {
        loadBackgroundForHour(System.getClockTime().hour);

        var background = mBackground;
        if (background == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            return;
        }
        dc.drawBitmap(0, 0, background);
    }

    // Swaps mBackground to the given hour's pre-rotated bitmap, but only
    // if it isn't already loaded -- WatchUi.loadResource() decodes into
    // memory, so this must not run on every single onUpdate/onPartialUpdate
    // call (that's the whole reason it's lazy instead of preloading all 24
    // in onLayout, which throws Out Of Memory -- see mBackground comment).
    private function loadBackgroundForHour(hour as Number) as Void {
        if (hour == mBackgroundHour && mBackground != null) {
            return;
        }
        mBackgroundHour = hour;
        mBackground = WatchUi.loadResource(mBackgroundIds[hour]) as WatchUi.BitmapResource;
    }

    // Draws a small icon followed by left-justified value text, icon's
    // left edge pinned at x. Falls back to text-only if the icon failed
    // to load (e.g. unsupported palette on some device/simulator combos).
    private function drawIconValueLeft(dc as Graphics.Dc, icon as WatchUi.BitmapResource?, x as Number, y as Number, valueStr as String) as Void {
        if (icon != null) {
            dc.drawBitmap(x, y - 1, icon);
            dc.drawText(x + icon.getWidth() + 3, y, Graphics.FONT_XTINY, valueStr, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(x, y, Graphics.FONT_XTINY, valueStr, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Draws right-justified value text ending at x, with a small icon
    // placed immediately to its left.
    private function drawIconValueRight(dc as Graphics.Dc, icon as WatchUi.BitmapResource?, x as Number, y as Number, valueStr as String) as Void {
        dc.drawText(x, y, Graphics.FONT_XTINY, valueStr, Graphics.TEXT_JUSTIFY_RIGHT);
        if (icon != null) {
            var textWidth = dc.getTextWidthInPixels(valueStr, Graphics.FONT_XTINY);
            dc.drawBitmap(x - textWidth - icon.getWidth() - 3, y - 1, icon);
        }
    }

    // Shows when the background heading last actually refreshed (see
    // HeadingServiceDelegate) -- otherwise there's no way to tell, since
    // Garmin throttles the real wake interval and the screen doesn't
    // redraw the instant new data lands. "--:--" if no background update
    // has landed yet (e.g. right after install, before the first wake).
    private function drawHeadingSyncTime(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var hour = Storage.getValue("backgroundHeadingHour");
        var minute = Storage.getValue("backgroundHeadingMinute");
        var timeStr = (hour != null && minute != null)
            ? Lang.format("$1$:$2$", [(hour as Number).format("%02d"), (minute as Number).format("%02d")])
            : "--:--";

        var drawX = x;
        var icon = mIconSyncTime;
        if (icon != null) {
            dc.drawBitmap(drawX, y - 1, icon);
            drawX += icon.getWidth() + 3;
        }
        dc.drawText(drawX, y, Graphics.FONT_XTINY, timeStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Draws the outer bezel circle and four cardinal tick marks (N/E/S/W).
    // dc.drawCircle(cx, cy, r) draws a circle outline — there is no filled
    // arc shorthand, so compass needles must be computed with sin/cos.
    // Live heading via Sensor.getInfo().heading requires the Sensor +
    // Background permissions and foreground/background annotations — see
    // README "Known gaps" for the upgrade path.
    // The background is a bold two-tone graphic (see manyBg.png in the repo
    // root) rather than an even, low-contrast texture, so a plain white
    // stroke can land on a white region and disappear. Every stroke here is
    // drawn twice — a wider black halo first, then the white line on top —
    // so the ring and ticks stay visible regardless of what's underneath.
    private function drawCompassRing(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawCircle(cx, cy, r);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
            var whiteWidth = (i == 0) ? 3 : 1;

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(whiteWidth + 2);
            dc.drawLine(x1, y1, x2, y2);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.setPenWidth(whiteWidth);
            dc.drawLine(x1, y1, x2, y2);
        }
        dc.setPenWidth(1); // Restore pen width
    }

    // Activity's heading is only populated during a tracked activity, which
    // is most of the time null. HeadingServiceDelegate (see that file and
    // UtilityFaceApp.getServiceDelegate/onBackgroundData) refreshes
    // "backgroundHeading" in Storage every few minutes via a proper
    // Background-permission service -- a plain Sensor.getInfo() call
    // isn't allowed directly in onUpdate for a watchface app type (the
    // manifest validator requires Background permission for the Sensor
    // permission, which in turn requires the full ServiceDelegate
    // architecture; see git history for the dead end that confirmed this).
    // Prefer the background-refreshed value; fall back to Activity's live
    // one when an activity happens to be recording.
    private function getHeading() as Float? {
        var bg = Storage.getValue("backgroundHeading");
        if (bg != null) {
            return bg as Float;
        }

        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null && activityInfo.currentHeading != null) {
            return activityInfo.currentHeading;
        }
        return null;
    }

    private function drawTimeLeft(dc as Graphics.Dc, cx_main as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx_main, 14, Graphics.FONT_NUMBER_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawSecondsLeft(dc as Graphics.Dc, cx_main as Number) as Void {
        var clock = System.getClockTime();
        var secStr = clock.sec.format("%02d");
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        
        var timeWidth = dc.getTextWidthInPixels(timeStr, Graphics.FONT_NUMBER_MEDIUM);
        var x = cx_main + (timeWidth / 2) + 4;
        var y = 18;
        
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
        
        // Opaque black text backgrounds (see drawIconValueLeft/Right comment)
        // paint over whatever's underneath, including an adjacent text draw --
        // these two lines need real clearance or the value's background
        // erases the label above it. FONT_SMALL's line-height box is taller
        // than it looks, so give this more room than seems necessary.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy - 30, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy - 10, Graphics.FONT_SMALL, (hr != null ? hr.toString() : "--"), Graphics.TEXT_JUSTIFY_CENTER);
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
        var o2Str = "O2 " + (spo2 != null ? (spo2 as Float).format("%.0f") + "%" : "--");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(24, cy - 30, Graphics.FONT_SMALL, o2Str, Graphics.TEXT_JUSTIFY_LEFT);

        // Only the subscreen layout has room for this: HR lives in its own
        // circular badge here rather than inline on this row, so there's
        // space after O2 for it. The non-subscreen layout puts "HR xx" at
        // x=24 on this same row, leaving essentially no gap before O2 --
        // it wouldn't fit there without overlapping, so it's subscreen-only.
        var o2Width = dc.getTextWidthInPixels(o2Str, Graphics.FONT_SMALL);
        drawHeadingSyncTime(dc, 24 + o2Width + 6, cy - 30);
    }

    // System.getClockTime() returns a ClockTime struct (hour, min, sec).
    // Lang.format() is Monkey C's printf equivalent — $1$, $2$ are
    // positional placeholders. format("%02d") zero-pads to two digits.
    // FONT_NUMBER_MEDIUM is a large digit-optimised font included in the SDK;
    // it renders more cleanly than a scaled general font for numeric displays.
    private function drawTime(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawIconValueLeft(dc, mIconAltitude, 24, cy + 6,
            (alt != null ? (alt as Float).format("%.0f") + "m" : "--"));

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
        drawIconValueRight(dc, mIconTemperature, w - 24, cy + 6,
            (temp != null ? (temp as Float).format("%.0f") + "C" : "--"));
    }

    // System.getSystemStats() returns device-level stats: battery (0–100 Float),
    // charging state, memory usage, etc. — a cheap synchronous call with no
    // permission requirements. ActivityMonitor.getInfo().steps is the day's
    // running step count, tracked on-watch and reset at midnight; also no
    // extra permission beyond what's already declared.
    private function drawStatusRow(dc as Graphics.Dc, cy as Number, w as Number) as Void {
        var stats = System.getSystemStats();
        var y = cy + 25;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawIconValueLeft(dc, mIconBattery, 24, y, stats.battery.format("%d") + "%");

        var steps = null;
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) {
            steps = info.steps;
        }
        drawIconValueRight(dc, mIconSteps, w - 24, y, (steps != null ? steps.toString() : "--"));
    }

    // Gregorian.info(moment, format) converts a Time.Moment (Unix-epoch-based
    // opaque type) into a human-readable struct with day_of_week, day, month,
    // year fields. TIME_FORMAT_MEDIUM returns localised short strings for
    // day/month names (e.g. "Wed", "Jul") rather than raw integers.
    private function drawDate(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.day, now.month]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy + 44, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
