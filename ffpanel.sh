#!/usr/bin/env bash
set -euo pipefail
ROOT="FFPanel"
rm -rf "$ROOT"
mkdir -p "$ROOT/app/src/main/java/com/vanta/ffpanel" \
         "$ROOT/app/src/main/res/layout" \
         "$ROOT/app/src/main/res/values" \
         "$ROOT/app/src/main/res/xml" \
         "$ROOT/app/src/main/assets"

# ============ Gradle ============
cat > "$ROOT/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
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
    buildTypes { release { isMinifyEnabled = false } }
    androidResources { noCompress += "tflite" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
}
EOF

# ============ Manifest ============
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
        android:label="@string/app_name"
        android:theme="@style/Theme.FFPanel">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".ScreenCaptureService" android:exported="false"
            android:foregroundServiceType="mediaProjection"/>
        <service android:name=".OverlayService" android:exported="false"
            android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="overlay_esp"/>
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

# ============ Resources ============
cat > "$ROOT/app/src/main/res/values/strings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FF Panel</string>
    <string name="accessibility_desc">Tap assist for FF Panel camera drag</string>
</resources>
EOF
cat > "$ROOT/app/src/main/res/values/themes.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.FFPanel" parent="Theme.Material3.Dark.NoActionBar"/>
</resources>
EOF
cat > "$ROOT/app/src/main/res/xml/accessibility_service_config.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeAllMask"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="50"
    android:canRetrieveWindowContent="false"
    android:canPerformGestures="true"
    android:description="@string/accessibility_desc" />
EOF
cat > "$ROOT/app/src/main/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical" android:padding="16dp"
    android:layout_width="match_parent" android:layout_height="match_parent">
    <TextView android:id="@+id/statusText" android:text="جاهز"
        android:textSize="18sp" android:layout_marginBottom="12dp"
        android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    <Switch android:id="@+id/espSwitch" android:text="ESP" android:checked="true"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <Switch android:id="@+id/aimSwitch" android:text="Aimbot"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/aimFovInput" android:hint="FOV (px)"
        android:text="250" android:inputType="number"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <Button android:id="@+id/btnAttach" android:text="Accessibility Settings"
        android:layout_marginTop="12dp"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <Button android:id="@+id/btnStart" android:text="Start"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <Button android:id="@+id/btnStop" android:text="Stop"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
</LinearLayout>
EOF

# ============ Kotlin ============
cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/DetectionBridge.kt" <<'EOF'
package com.vanta.ffpanel

data class Detection(
    val left: Float, val top: Float, val right: Float, val bottom: Float,
    val score: Float
) {
    val cx get() = (left + right) / 2f
    val cy get() = (top + bottom) / 2f
}

object DetectionBridge {
    @Volatile var latest: List<Detection> = emptyList()
    @Volatile var screenW: Int = 0
    @Volatile var screenH: Int = 0
    @Volatile var aimActive: Boolean = false
    @Volatile var fovPx: Int = 250
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

    companion object {
        private const val MODEL_FILE = "efficientdet-lite0.tflite"
        private const val INPUT_SIZE = 320
        private const val MAX_DET = 25
        private const val SCORE_THRESHOLD = 0.45f
        private const val PERSON_CLASS = 0
    }

    private val interpreter: Interpreter
    private val inputBuffer: ByteBuffer
    private val isQuantInput: Boolean
    private val locOut = Array(1) { Array(MAX_DET) { FloatArray(4) } }
    private val catOut = Array(1) { FloatArray(MAX_DET) }
    private val scoreOut = Array(1) { FloatArray(MAX_DET) }
    private val numOut = FloatArray(1)
    private val outMap = HashMap<Int, Any>()

    init {
        interpreter = Interpreter(loadModel(context), Interpreter.Options().apply { setNumThreads(4) })
        isQuantInput = interpreter.getInputTensor(0).dataType() == DataType.UINT8
        inputBuffer = ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3 * 4)
            .order(ByteOrder.nativeOrder())
        outMap[findOutput("location", 0)] = locOut
        outMap[findOutput("category", 1)] = catOut
        outMap[findOutput("score", 2)] = scoreOut
        outMap[findOutput("number of detections", 3)] = numOut
    }

    private fun findOutput(name: String, fallback: Int): Int =
        try { interpreter.getOutputIndex(name) } catch (_: Throwable) { fallback }

    fun detect(frame: Bitmap): List<Detection> {
        val scaled = Bitmap.createScaledBitmap(frame, INPUT_SIZE, INPUT_SIZE, true)
        inputBuffer.rewind()
        val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
        scaled.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
        if (isQuantInput) {
            for (p in pixels) {
                inputBuffer.put(((p shr 16) and 0xFF).toByte())
                inputBuffer.put(((p shr 8) and 0xFF).toByte())
                inputBuffer.put((p and 0xFF).toByte())
            }
        } else {
            for (p in pixels) {
                inputBuffer.putFloat(((p shr 16) and 0xFF) / 255f)
                inputBuffer.putFloat(((p shr 8) and 0xFF) / 255f)
                inputBuffer.putFloat((p and 0xFF) / 255f)
            }
        }
        inputBuffer.rewind()
        interpreter.runForMultipleInputsOutputs(arrayOf(inputBuffer), outMap)
        if (scaled !== frame) scaled.recycle()

        val count = numOut[0].toInt().coerceIn(0, MAX_DET)
        val sw = DetectionBridge.screenW; val sh = DetectionBridge.screenH
        if (sw <= 0 || sh <= 0) return emptyList()

        val out = ArrayList<Detection>(count)
        for (i in 0 until count) {
            if (scoreOut[0][i] < SCORE_THRESHOLD) continue
            if (catOut[0][i].toInt() != PERSON_CLASS) continue
            val b = locOut[0][i]
            out.add(Detection(b[1] * sw, b[0] * sh, b[3] * sw, b[2] * sh, scoreOut[0][i]))
        }
        return out
    }

    private fun loadModel(context: Context): MappedByteBuffer {
        context.assets.openFd(MODEL_FILE).use { fd ->
            FileInputStream(fd.fileDescriptor).use { fis ->
                return fis.channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
            }
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
        private const val NOTIF_ID = 2
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null
    private var detector: Detector? = null
    private var screenW = 0; private var screenH = 0; private var density = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        if (data == null) { stopSelf(); return START_NOT_STICKY }

        startForegroundNotification()
        val dm = resources.displayMetrics
        screenW = dm.widthPixels
        screenH = dm.heightPixels
        density = dm.densityDpi
        DetectionBridge.screenW = screenW
        DetectionBridge.screenH = screenH

        bgThread = HandlerThread("ffpanel-capture").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)
        detector = Detector(this)

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data) ?: run { stopSelf(); return START_NOT_STICKY }
        if (Build.VERSION.SDK_INT >= 31) {
            mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, bgHandler)
        }
        imageReader = ImageReader.newInstance(screenW, screenH, PixelFormat.RGBA_8888, 2)
        imageReader!!.setOnImageAvailableListener({ r -> onFrame(r) }, bgHandler)
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "ffpanel-vd", screenW, screenH, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, bgHandler
        )
        return START_STICKY
    }

    private fun onFrame(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        try {
            val plane = image.planes[0]
            val pixelStride = plane.pixelStride; val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * screenW
            val paddedW = screenW + rowPadding / pixelStride
            val bmp = Bitmap.createBitmap(paddedW, screenH, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(plane.buffer)
            val cropped = if (paddedW != screenW) Bitmap.createBitmap(bmp, 0, 0, screenW, screenH) else bmp
            DetectionBridge.latest = detector?.detect(cropped) ?: emptyList()
            if (cropped !== bmp) cropped.recycle()
            bmp.recycle()
        } catch (_: Throwable) {
        } finally { image.close() }
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL_ID, "FF Panel", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FF Panel").setContentText("Screen capture running")
            .setSmallIcon(android.R.drawable.ic_menu_view).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34)
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(NOTIF_ID, notif)
    }

    override fun onDestroy() {
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        try { imageReader?.close() } catch (_: Throwable) {}
        try { mediaProjection?.stop() } catch (_: Throwable) {}
        try { detector?.close() } catch (_: Throwable) {}
        bgThread?.quitSafely()
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
            handler.postDelayed(this, 80)
        }
    }

    override fun onServiceConnected() { super.onServiceConnected(); instance = this; handler.post(tick) }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    private fun tryAim() {
        val now = System.currentTimeMillis()
        if (now - lastAimMs < 130) return
        val sw = DetectionBridge.screenW; val sh = DetectionBridge.screenH
        if (sw <= 0 || sh <= 0) return
        val fov = DetectionBridge.fovPx.toFloat()
        val cx = sw / 2f; val cy = sh / 2f

        var best: Detection? = null; var bestD = Float.MAX_VALUE
        for (d in DetectionBridge.latest) {
            val dist = hypot(d.cx - cx, d.cy - cy)
            if (dist > fov) continue
            if (dist < bestD) { bestD = dist; best = d }
        }
        val target = best ?: return
        val dx = (target.cx - cx) * 0.35f
        val dy = (target.cy - cy) * 0.35f
        if (hypot(dx, dy) < 6f) return
        val path = Path().apply { moveTo(cx, cy); lineTo(cx + dx, cy + dy) }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 90)).build()
        dispatchGesture(g, null, null)
        lastAimMs = now
    }

    override fun onDestroy() { handler.removeCallbacks(tick); if (instance === this) instance = null; super.onDestroy() }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/OverlayService.kt" <<'EOF'
package com.vanta.ffpanel

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.NotificationCompat

class OverlayService : Service() {
    companion object { private const val CHANNEL_ID = "ffpanel_overlay"; private const val NOTIF_ID = 1 }
    private lateinit var wm: WindowManager
    private lateinit var view: OverlayView
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        DetectionBridge.aimActive = intent?.getBooleanExtra("aim", false) ?: false
        DetectionBridge.fovPx = intent?.getIntExtra("fov", 250) ?: 250
        DetectionBridge.showEsp = intent?.getBooleanExtra("esp", true) ?: true
        startForegroundNotification()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        view = OverlayView(this)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        wm.addView(view, params)
        handler.post(renderLoop)
        return START_STICKY
    }

    private val renderLoop = object : Runnable {
        override fun run() { view.invalidate(); handler.postDelayed(this, 16) }
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL_ID, "FF Panel", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        startForeground(NOTIF_ID, NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FF Panel").setContentText("Overlay running")
            .setSmallIcon(android.R.drawable.ic_menu_view).setOngoing(true).build())
    }

    override fun onDestroy() {
        handler.removeCallbacks(renderLoop)
        if (::view.isInitialized) wm.removeView(view)
        DetectionBridge.aimActive = false
        super.onDestroy()
    }
}

class OverlayView(ctx: Context) : android.view.View(ctx) {
    private val boxPaint = Paint().apply {
        color = Color.rgb(0, 255, 140); style = Paint.Style.STROKE
        strokeWidth = 3f; isAntiAlias = true
    }
    private val labelPaint = Paint().apply { color = Color.WHITE; textSize = 32f; isAntiAlias = true }
    private val fovPaint = Paint().apply {
        color = Color.argb(80, 255, 255, 255); style = Paint.Style.STROKE; strokeWidth = 2f
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val sw = DetectionBridge.screenW.toFloat(); val sh = DetectionBridge.screenH.toFloat()
        if (sw <= 0 || sh <= 0) return
        if (DetectionBridge.aimActive)
            canvas.drawCircle(sw / 2f, sh / 2f, DetectionBridge.fovPx.toFloat(), fovPaint)
        if (!DetectionBridge.showEsp) return
        for (d in DetectionBridge.latest) {
            canvas.drawRect(d.left, d.top, d.right, d.bottom, boxPaint)
            canvas.drawText("${(d.score * 100).toInt()}%", d.left, d.top - 8f, labelPaint)
        }
    }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/ffpanel/MainActivity.kt" <<'EOF'
package com.vanta.ffpanel

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.*
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    companion object { private const val REQ_CAPTURE = 1001; private const val REQ_NOTIF = 1002 }
    private lateinit var statusText: TextView
    private lateinit var espSwitch: Switch
    private lateinit var aimSwitch: Switch
    private lateinit var fovInput: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        statusText = findViewById(R.id.statusText)
        espSwitch = findViewById(R.id.espSwitch)
        aimSwitch = findViewById(R.id.aimSwitch)
        fovInput = findViewById(R.id.aimFovInput)

        if (Build.VERSION.SDK_INT >= 33)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        if (!Settings.canDrawOverlays(this))
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))

        findViewById<Button>(R.id.btnAttach).setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            statusText.text = "فعّل FF Panel في Accessibility"
        }
        findViewById<Button>(R.id.btnStart).setOnClickListener {
            if (!Settings.canDrawOverlays(this)) { statusText.text = "صلاحية overlay مطلوبة"; return@setOnClickListener }
            if (aimSwitch.isChecked && !isAccessibilityEnabled()) {
                statusText.text = "فعّل FF Panel في Accessibility أول"; return@setOnClickListener
            }
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE)
        }
        findViewById<Button>(R.id.btnStop).setOnClickListener {
            stopService(Intent(this, ScreenCaptureService::class.java))
            stopService(Intent(this, OverlayService::class.java))
            DetectionBridge.aimActive = false
            statusText.text = "متوقف"
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE) return
        if (resultCode != Activity.RESULT_OK || data == null) { statusText.text = "التقاط مرفوض"; return }
        val cap = Intent(this, ScreenCaptureService::class.java).apply {
            putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenCaptureService.EXTRA_DATA, data)
        }
        val ov = Intent(this, OverlayService::class.java).apply {
            putExtra("aim", aimSwitch.isChecked)
            putExtra("esp", espSwitch.isChecked)
            putExtra("fov", fovInput.text.toString().toIntOrNull() ?: 250)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(cap); startForegroundService(ov)
        } else { startService(cap); startService(ov) }
        statusText.text = "شغّال"
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val expected = "$packageName/${AimAccessibilityService::class.java.name}"
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }
}
EOF

# ============ Model download ============
MODEL="$ROOT/app/src/main/assets/efficientdet-lite0.tflite"
URL="https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/object_detection/android/lite-model_efficientdet_lite0_detection_metadata_1.tflite"
echo "[*] downloading model..."
if command -v curl >/dev/null 2>&1; then curl -L -o "$MODEL" "$URL"
elif command -v wget >/dev/null 2>&1; then wget -O "$MODEL" "$URL"
else echo "[!] نزّل الموديل يدوياً: $URL → $MODEL"; exit 1; fi

if [ ! -f "$ROOT/gradlew" ]; then
    if command -v gradle >/dev/null 2>&1; then (cd "$ROOT" && gradle wrapper --gradle-version 8.1)
    else echo "[!] Gradle غير موجود. جرّب تشغيل السكربت في GitHub Actions."; fi
fi

echo "[✓] المشروع جاهز في: $ROOT/"
