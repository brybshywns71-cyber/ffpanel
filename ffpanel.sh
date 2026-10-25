#!/usr/bin/env bash
set -euo pipefail
ROOT="FFPanel"
rm -rf "$ROOT"
mkdir -p "$ROOT/app/src/main/java/com/vanta/ffpanel" \
         "$ROOT/app/src/main/res/layout" \
         "$ROOT/app/src/main/res/values" \
         "$ROOT/app/src/main/res/xml" \
         "$ROOT/app/src/main/assets"

cat > "$ROOT/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF
cat > "$ROOT/settings.gradle.kts" <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "FFPanel"
include(":app")
EOF
cat > "$ROOT/gradle.properties" <<'EOF'
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

cat > "$ROOT/app/build.gradle.kts" <<'EOF'
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.vanta.ffpanel"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.vanta.ffpanel"
        minSdk = 26; targetSdk = 34
        versionCode = 1; versionName = "1.0"
    }
    buildTypes { 
        release { isMinifyEnabled = false } 
    }
    androidResources { noCompress += "tflite" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
}
EOF

cat > "$ROOT/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <application
        android:allowBackup="false"
        android:label="FF Panel"
        android:theme="@style/Theme.AppCompat.DayNight.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".ScreenCaptureService" android:exported="false" android:foregroundServiceType="mediaProjection"/>
        <service android:name=".OverlayService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="overlay"/>
        </service>
        <service android:name=".AimAccessibilityService" android:exported="true"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config"/>
        </service>
    </application>
</manifest>
EOF

cat > "$ROOT/app/src/main/res/xml/accessibility_service_config.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeAllMask"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:canRetrieveWindowContent="false"
    android:canPerformGestures="true"
    android:description="FF Panel Aim" />
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/DetectionBridge.kt" <<'EOF'
package com.vanta.ffpanel
data class Detection(val left: Float, val top: Float, val right: Float, val bottom: Float, val score: Float)
object DetectionBridge {
    @Volatile var latest: List<Detection> = emptyList()
    @Volatile var screenW: Int = 0
    @Volatile var screenH: Int = 0
    @Volatile var aimActive: Boolean = false
    @Volatile var fovPx: Int = 150
    @Volatile var showEsp: Boolean = true
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/Detector.kt" <<'EOF'
package com.vanta.ffpanel
import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

class Detector(context: Context) : AutoCloseable {
    private val interpreter: Interpreter
    private val inputBuffer: ByteBuffer
    private val isQuantInput: Boolean
    private val locOut = Array(1) { Array(10) { FloatArray(4) } }
    private val catOut = Array(1) { FloatArray(10) }
    private val scoreOut = Array(1) { FloatArray(10) }
    private val numOut = FloatArray(1)
    private val outMap = HashMap<Int, Any>()

    init {
        interpreter = Interpreter(loadModel(context), Interpreter.Options().apply { setNumThreads(2) })
        isQuantInput = interpreter.getInputTensor(0).dataType() == DataType.UINT8
        inputBuffer = ByteBuffer.allocateDirect(300 * 300 * 3 * 4).order(ByteOrder.nativeOrder())
        outMap[0] = locOut; outMap[1] = catOut; outMap[2] = scoreOut; outMap[3] = numOut
    }

    fun detect(frame: Bitmap): List<Detection> {
        val scaled = Bitmap.createScaledBitmap(frame, 300, 300, true)
        inputBuffer.rewind()
        val pixels = IntArray(300 * 300)
        scaled.getPixels(pixels, 0, 300, 0, 0, 300, 300)
        if (isQuantInput) {
            for (p in pixels) { inputBuffer.put(((p shr 16) and 0xFF).toByte()); inputBuffer.put(((p shr 8) and 0xFF).toByte()); inputBuffer.put((p and 0xFF).toByte()) }
        } else {
            for (p in pixels) { inputBuffer.putFloat(((p shr 16) and 0xFF) / 255f); inputBuffer.putFloat(((p shr 8) and 0xFF) / 255f); inputBuffer.putFloat((p and 0xFF) / 255f) }
        }
        inputBuffer.rewind()
        interpreter.runForMultipleInputsOutputs(arrayOf(inputBuffer), outMap)
        if (scaled !== frame) scaled.recycle()

        val count = numOut[0].toInt().coerceIn(0, 10)
        val sw = DetectionBridge.screenW; val sh = DetectionBridge.screenH
        if (sw <= 0 || sh <= 0) return emptyList()
        val out = ArrayList<Detection>(count)
        for (i in 0 until count) {
            if (scoreOut[0][i] < 0.50f || catOut[0][i].toInt() != 0) continue
            val b = locOut[0][i]
            out.add(Detection(b[1] * sw, b[0] * sh, b[3] * sw, b[2] * sh, scoreOut[0][i]))
        }
        return out
    }
    private fun loadModel(context: Context): MappedByteBuffer {
        context.assets.openFd("ssd_mobilenet.tflite").use { fd ->
            FileInputStream(fd.fileDescriptor).use { fis -> return fis.channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength) }
        }
    }
    override fun close() { try { interpreter.close() } catch (_: Throwable) {} }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/ScreenCaptureService.kt" <<'EOF'
package com.vanta.ffpanel
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import androidx.core.app.NotificationCompat

class ScreenCaptureService : Service() {
    companion object {
        private const val CHANNEL_ID = "ffpanel_capture"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"
    }
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null
    private var detector: Detector? = null
    private var screenW = 0; private var screenH = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(EXTRA_DATA, Intent::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        if (data == null) { stopSelf(); return START_NOT_STICKY }

        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL_ID, "FF", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID).setContentTitle("FF").setSmallIcon(android.R.drawable.ic_menu_view).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(2, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION) else startForeground(2, notif)

        val dm = resources.displayMetrics
        screenW = dm.widthPixels; screenH = dm.heightPixels
        DetectionBridge.screenW = screenW; DetectionBridge.screenH = screenH

        bgThread = HandlerThread("capture").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)
        detector = Detector(this)

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)
        imageReader = ImageReader.newInstance(screenW, screenH, PixelFormat.RGBA_8888, 2)
        imageReader!!.setOnImageAvailableListener({ r -> onFrame(r) }, bgHandler)
        virtualDisplay = mediaProjection!!.createVirtualDisplay("vd", screenW, screenH, dm.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, imageReader!!.surface, null, bgHandler)
        return START_STICKY
    }

    private fun onFrame(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        try {
            val plane = image.planes[0]
            val rowPadding = plane.rowStride - plane.pixelStride * screenW
            val paddedW = screenW + rowPadding / plane.pixelStride
            val bmp = Bitmap.createBitmap(paddedW, screenH, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(plane.buffer)
            val cropped = if (paddedW != screenW) Bitmap.createBitmap(bmp, 0, 0, screenW, screenH) else bmp
            DetectionBridge.latest = detector?.detect(cropped) ?: emptyList()
            if (cropped !== bmp) cropped.recycle()
            bmp.recycle()
        } catch (_: Throwable) {} finally { image.close() }
    }

    override fun onDestroy() {
        try { virtualDisplay?.release(); imageReader?.close(); mediaProjection?.stop(); detector?.close(); bgThread?.quitSafely() } catch (_: Throwable) {}
        super.onDestroy()
    }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/AimAccessibilityService.kt" <<'EOF'
package com.vanta.ffpanel
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import kotlin.math.hypot

class AimAccessibilityService : AccessibilityService() {
    companion object { @Volatile var instance: AimAccessibilityService? = null }
    private val handler = Handler(Looper.getMainLooper())
    private var lastAimMs = 0L

    private val tick = object : Runnable {
        override fun run() {
            if (DetectionBridge.aimActive) tryAim()
            handler.postDelayed(this, 20)
        }
    }
    override fun onServiceConnected() { super.onServiceConnected(); instance = this; handler.post(tick) }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    private fun tryAim() {
        val now = System.currentTimeMillis()
        if (now - lastAimMs < 50) return 
        val sw = DetectionBridge.screenW; val sh = DetectionBridge.screenH
        val fov = DetectionBridge.fovPx.toFloat()
        val cx = sw / 2f; val cy = sh / 2f
        var best: Detection? = null; var bestD = Float.MAX_VALUE
        for (d in DetectionBridge.latest) {
            val dist = hypot((d.left + d.right) / 2f - cx, (d.top + (d.bottom - d.top) * 0.05f) - cy)
            if (dist < fov && dist < bestD) { bestD = dist; best = d }
        }
        val target = best ?: return
        val dx = ((target.left + target.right) / 2f - cx) * 0.4f
        val dy = ((target.top + (target.bottom - target.top) * 0.05f) - cy) * 0.4f
        if (hypot(dx, dy) < 3f) return
        val path = Path().apply { moveTo(cx, cy); lineTo(cx + dx, cy + dy) }
        dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 20)).build(), null, null)
        lastAimMs = now
    }
    override fun onDestroy() { handler.removeCallbacks(tick); instance = null; super.onDestroy() }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/OverlayService.kt" <<'EOF'
package com.vanta.ffpanel
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.*
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import androidx.core.app.NotificationCompat

class OverlayService : Service() {
    private lateinit var wm: WindowManager
    private lateinit var espView: ESPView
    private lateinit var panelView: LinearLayout

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        DetectionBridge.aimActive = intent?.getBooleanExtra("aim", false) ?: false
        DetectionBridge.fovPx = intent?.getIntExtra("fov", 150) ?: 150
        DetectionBridge.showEsp = intent?.getBooleanExtra("esp", true) ?: true

        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel("ov", "FF", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, "ov").setContentTitle("FF").setSmallIcon(android.R.drawable.ic_menu_view).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(1, notif)

        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        espView = ESPView(this)
        wm.addView(espView, WindowManager.LayoutParams(-1, -1, if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT))

        panelView = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.parseColor("#CC000000")); setPadding(40, 40, 40, 40) }
        panelView.addView(TextView(this).apply { text = "FF PANEL"; setTextColor(Color.GREEN); textSize = 20f })
        panelView.addView(Switch(this).apply { text = "ESP"; setTextColor(Color.WHITE); isChecked = DetectionBridge.showEsp; setOnCheckedChangeListener { _, b -> DetectionBridge.showEsp = b } })
        panelView.addView(Switch(this).apply { text = "Aimbot"; setTextColor(Color.WHITE); isChecked = DetectionBridge.aimActive; setOnCheckedChangeListener { _, b -> DetectionBridge.aimActive = b } })

        val p = WindowManager.LayoutParams(-2, -2, if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT)
        p.gravity = Gravity.TOP or Gravity.START; p.x = 50; p.y = 100
        panelView.setOnTouchListener(object : View.OnTouchListener {
            var ix = 0; var iy = 0; var itx = 0f; var ity = 0f
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                if (e.action == MotionEvent.ACTION_DOWN) { ix = p.x; iy = p.y; itx = e.rawX; ity = e.rawY; return true }
                if (e.action == MotionEvent.ACTION_MOVE) { p.x = ix + (e.rawX - itx).toInt(); p.y = iy + (e.rawY - ity).toInt(); wm.updateViewLayout(panelView, p); return true }
                return false
            }
        })
        wm.addView(panelView, p)
        return START_STICKY
    }
    override fun onDestroy() {
        if (::espView.isInitialized) wm.removeView(espView)
        if (::panelView.isInitialized) wm.removeView(panelView)
        super.onDestroy()
    }
}
class ESPView(c: Context) : View(c) {
    private val b = Paint().apply { color = Color.GREEN; style = Paint.Style.STROKE; strokeWidth = 4f }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!DetectionBridge.showEsp) return
        for (d in DetectionBridge.latest) canvas.drawRect(d.left, d.top, d.right, d.bottom, b)
        invalidate()
    }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/MainActivity.kt" <<'EOF'
package com.vanta.ffpanel
import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.*
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        val l = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(50, 50, 50, 50) }
        val s1 = Switch(this).apply { text = "ESP" }
        val s2 = Switch(this).apply { text = "Aim" }
        val f = EditText(this).apply { setText("150") }
        val b1 = Button(this).apply { text = "Start"; setOnClickListener { 
            if (!Settings.canDrawOverlays(this@MainActivity)) startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))) 
            else { val i = (getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager).createScreenCaptureIntent(); startActivityForResult(i, 1) }
        } }
        l.addView(s1); l.addView(s2); l.addView(f); l.addView(b1)
        setContentView(l)
    }
    override fun onActivityResult(r: Int, c: Int, d: Intent?) {
        if (r == 1 && c == Activity.RESULT_OK && d != null) {
            startService(Intent(this, ScreenCaptureService::class.java).putExtra("resultCode", c).putExtra("data", d))
            startService(Intent(this, OverlayService::class.java))
        }
    }
}
EOF

MODEL="$ROOT/app/src/main/assets/ssd_mobilenet.tflite"
URL="https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/object_detection/android/lite-model_ssd_mobilenet_v1_1_metadata_2.tflite"
if command -v curl >/dev/null 2>&1; then curl -L -o "$MODEL" "$URL"; fi

echo "[✓] Project ready: $ROOT/"
