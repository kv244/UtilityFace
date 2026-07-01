import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;
import Toybox.Math;

class UtilityFaceView extends WatchUi.WatchFace {

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
    }

    function onExitSleep() as Void {
    }

    function onEnterSleep() as Void {
    }

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

    function onPartialUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var clock = System.getClockTime();
        var secStr = clock.sec.format("%02d");

        var boxW = 40;
        var boxH = 20;
        var x = (w / 2) + 34;
        var y = 18;

        dc.setClip(x, y, boxW, boxH);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(x, y, boxW, boxH);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.clearClip();
    }

    // --- Drawing helpers -----------------------------------------------

    private function drawCompassRing(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, r);

        // Static cardinal tick marks at N/E/S/W (degrees clockwise from north)
        var cardinalDegs = [0.0, 90.0, 180.0, 270.0] as Array<Float>;
        for (var i = 0; i < cardinalDegs.size(); i++) {
            var angle = cardinalDegs[i] * Math.PI / 180.0 - Math.PI / 2.0;
            var tickInner = r - 8;
            var x1 = cx + (tickInner * Math.cos(angle)).toNumber();
            var y1 = cy + (tickInner * Math.sin(angle)).toNumber();
            var x2 = cx + (r * Math.cos(angle)).toNumber();
            var y2 = cy + (r * Math.sin(angle)).toNumber();
            dc.drawLine(x1, y1, x2, y2);
        }
    }

    private function drawTime(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 14, Graphics.FONT_NUMBER_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

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
        dc.drawText(w - 18, cy - 30, Graphics.FONT_SMALL,
            "O2 " + (spo2 != null ? (spo2 as Float).format("%.0f") + "%" : "--"), Graphics.TEXT_JUSTIFY_RIGHT);
    }

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

    private function drawDate(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [now.day_of_week, now.day, now.month]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 26, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
