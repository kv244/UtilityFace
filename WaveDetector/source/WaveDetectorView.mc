import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Sensor;
import Toybox.Lang;
import Toybox.Math;

// Prototype accelerometer-based motion/wave counter -- NOT a validated surf
// wave-detection algorithm, just a starting point (see ../UtilityFace's
// MEMORY.md next step 6). The heuristic: track the magnitude of the
// accelerometer vector, smooth it with an exponential moving average to
// filter out high-frequency jitter, then count a "wave" every time the
// smoothed deviation from resting gravity rises above a high threshold
// after having settled below a lower one (hysteresis, so noise sitting
// between the two thresholds can't double-count a single motion).
class WaveDetectorView extends WatchUi.View {

    // Resting magnitude of gravity in the units Sensor.AccelerometerData
    // reports (milli-Gs): 1 G == 1000.
    const GRAVITY_MG = 1000.0;

    // Smoothing factor for the exponential moving average (0..1); higher
    // = more responsive/noisier, lower = smoother/slower.
    const EMA_ALPHA = 0.2;

    // Hysteresis thresholds (mG deviation from gravity) for counting one
    // "wave". Unvalidated guesses, not tuned against real surf motion.
    const THRESHOLD_HIGH = 250.0;
    const THRESHOLD_LOW = 100.0;

    private var mEmaDeviation as Float = 0.0;
    private var mArmed as Boolean = true;
    private var mWaveCount as Number = 0;
    private var mListening as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        startListening();
    }

    function onHide() as Void {
        stopListening();
    }

    private function startListening() as Void {
        if (mListening) {
            return;
        }
        var options = {
            :period => 1,
            :accelerometer => {
                :enabled => true,
                :sampleRate => 25
            }
        };
        Sensor.registerSensorDataListener(method(:onSensorData), options);
        mListening = true;
    }

    private function stopListening() as Void {
        if (!mListening) {
            return;
        }
        Sensor.unregisterSensorDataListener();
        mListening = false;
    }

    // Bound to SELECT via WaveDetectorDelegate.
    function resetCount() as Void {
        mWaveCount = 0;
        mArmed = true;
        WatchUi.requestUpdate();
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        var accel = sensorData.accelerometerData;
        if (accel == null) {
            return;
        }
        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) {
            return;
        }

        for (var i = 0; i < xs.size(); i++) {
            var x = xs[i];
            var y = ys[i];
            var z = zs[i];
            if (x == null || y == null || z == null) {
                continue;
            }
            var mag = Math.sqrt((x * x + y * y + z * z).toFloat()).toFloat();
            processSample(mag);
        }

        WatchUi.requestUpdate();
    }

    private function processSample(mag as Float) as Void {
        var deviation = (mag - GRAVITY_MG).toFloat();
        if (deviation < 0.0) {
            deviation = -deviation;
        }
        mEmaDeviation = (mEmaDeviation * (1.0 - EMA_ALPHA)) + (deviation * EMA_ALPHA);

        // Only re-arm once motion settles below the low threshold; only
        // count once it then rises above the high one.
        if (mEmaDeviation < THRESHOLD_LOW) {
            mArmed = true;
        } else if (mArmed && mEmaDeviation > THRESHOLD_HIGH) {
            mWaveCount++;
            mArmed = false;
        }
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.drawText(cx, cy - 60, Graphics.FONT_SMALL, "WAVES", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy - 40, Graphics.FONT_NUMBER_HOT, mWaveCount.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        var statusStr = mListening ? "listening" : "stopped";
        dc.drawText(cx, cy + 30, Graphics.FONT_XTINY, statusStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 46, Graphics.FONT_XTINY, "motion " + mEmaDeviation.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 62, Graphics.FONT_XTINY, "SELECT resets", Graphics.TEXT_JUSTIFY_CENTER);
    }

}
