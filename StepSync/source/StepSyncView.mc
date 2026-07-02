import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.ActivityMonitor;
import Toybox.System;

class StepSyncView extends WatchUi.View {

    private var mBleDelegate as StepSyncBleDelegate?;

    function initialize(bleDelegate as StepSyncBleDelegate?) {
        View.initialize();
        mBleDelegate = bleDelegate;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // Clear the screen with a clean white text on black background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var squareSize = (w < h ? w : h);
        var cy = squareSize / 2;

        // Fetch current day's step count
        var steps = 0;
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) {
            steps = info.steps as Number;
        }

        // Fetch BLE status and last sync time
        var status = "Unknown";
        var syncTime = "Never";
        var bleDelegate = mBleDelegate;
        if (bleDelegate != null) {
            status = bleDelegate.mStatus;
            syncTime = bleDelegate.mLastSyncStr;
        }

        var gap = 4;
        var lines = [
            ["DAILY STEPS", Graphics.FONT_SMALL],
            [steps.toString(), Graphics.FONT_NUMBER_HOT],
            ["BLE: " + status, Graphics.FONT_TINY],
            ["Sync: " + syncTime, Graphics.FONT_XTINY],
            ["SELECT: Manual Sync", Graphics.FONT_XTINY],
        ];

        // Measure heights dynamically to center elements on any screen geometry
        var totalHeight = 0;
        for (var i = 0; i < lines.size(); i++) {
            totalHeight += dc.getFontHeight(lines[i][1]);
        }
        totalHeight += gap * (lines.size() - 1);

        var y = cy - (totalHeight / 2);
        for (var i = 0; i < lines.size(); i++) {
            var font = lines[i][1];
            dc.drawText(cx, y, font, lines[i][0], Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(font) + gap;
        }
    }
}
