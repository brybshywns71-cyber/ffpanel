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
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
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
    <string name="accessibility_desc">Tap assist for FF Panel</string>
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

class Detector(context: Context) : AutoCloseable {
    fun detect(frame: Bitmap): List<Detection> {
        return emptyList() // AI disabled to prevent crash on low RAM
    }
    override fun close() {}
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
        val data = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(EXTRA_DATA, Intent::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        if (data == null) { stopSelf(); return START_NOT_STICKY }

        startForegroundNotification()
        val dm = resources.displayMetrics
        screenW = dm.widthPixels; screenH = dm.heightPixels; density = dm.densityDpi
        DetectionBridge.screenW = screenW; DetectionBridge.screenH = screenH

        bgThread = HandlerThread("ffpanel-capture").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)
        detector = Detector(this)

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data) ?: run { stopSelf(); return START_NOT_STICKY }
        if (Build.VERSION.SDK_INT >= 31) {
            mediaProjection!!.registerCallback(object : MediaProjection.Callback() { override fun onStop() { stopSelf() } }, bgHandler)
        }
        imageReader = ImageReader.newInstance(screenW, screenH, PixelFormat.RGBA_8888, 2)
        imageReader!!.setOnImageAvailableListener({ r -> onFrame(r) }, bgHandler)
        virtualDisplay = mediaProjection!!.createVirtualDisplay("ffpanel-vd", screenW, screenH, density, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, imageReader!!.surface, null, bgHandler)
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

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL_ID, "FF Panel", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID).setContentTitle("FF Panel").setContentText("Running").setSmallIcon(android.R.drawable.ic_menu_view).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION) else startForeground(NOTIF_ID, notif)
    }

    override fun onDestroy() {
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        try { imageReader?.close() } catch (_: Throwable) {}
        try { mediaProjection?.stop() } catch (_: Throwable) {}
        try { detector?.close() } catch (_: Throwable) {}
        bgThread?.quitSafely(); super.onDestroy()
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
            handler.postDelayed(this, 30)
        }
    }

    override fun onServiceConnected() { super.onServiceConnected(); instance = this; handler.post(tick) }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    private fun tryAim() {
        val now = System.currentTimeMillis()
        if (now - lastAimMs < 60) return
        
        val sw = DetectionBridge.screenW; val sh = DetectionBridge.screenH
        if (sw <= 0 || sh <= 0) return
        val fov = DetectionBridge.fovPx.toFloat()
        val cx = sw / 2f; val cy = sh / 2f

        var best: Detection? = null; var bestD = Float.MAX_VALUE
        for (d in DetectionBridge.latest) {
            val targetX = (d.left + d.right) / 2f
            val targetY = d.top + (d.bottom - d.top) * 0.2f
            val dist = hypot(targetX - cx, targetY - cy)
            if (dist > fov) continue
            if (dist < bestD) { bestD = dist; best = d }
        }
        
        val target = best ?: return
        val tX = (target.left + target.right) / 2f
        val tY = target.top + (target.bottom - target.top) * 0.2f
        val dx = (tX - cx) * 0.20f 
        val dy = (tY - cy) * 0.20f
        
        if (hypot(dx, dy) < 4f) return
        
        val path = Path().apply { moveTo(cx, cy); lineTo(cx + dx, cy + dy) }
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 50)).build()
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
        DetectionBridge.fovPx = intent?.getIntExtra("fov", 250) ?: 250
        DetectionBridge.showEsp = intent?.getBooleanExtra("esp", true) ?: true

        startForegroundNotification()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        espView = ESPView(this)
        val espParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        wm.addView(espView, espParams)
        setupPanelView()
        return START_STICKY
    }

    private fun setupPanelView() {
        panelView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC000000"))
            setPadding(30, 30, 30, 30)
            alpha = 0.8f
        }
        val title = TextView(this).apply {
            text = "FF PANEL"
            setTextColor(Color.GREEN)
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 20)
        }
        panelView.addView(title)

        val espSwitch = Switch(this).apply {
            text = " ESP"
            setTextColor(Color.WHITE)
            isChecked = DetectionBridge.showEsp
            setOnCheckedChangeListener { _, isChecked -> DetectionBridge.showEsp = isChecked }
        }
        panelView.addView(espSwitch)

        val aimSwitch = Switch(this).apply {
            text = " Aimbot"
            setTextColor(Color.WHITE)
            isChecked = DetectionBridge.aimActive
            setOnCheckedChangeListener { _, isChecked -> DetectionBridge.aimActive = isChecked }
        }
        panelView.addView(aimSwitch)

        val panelParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        panelParams.gravity = Gravity.TOP or Gravity.START
        panelParams.x = 50; panelParams.y = 100

        panelView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0; private var initialY = 0
            private var initialTouchX = 0f; private var initialTouchY = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = panelParams.x; initialY = panelParams.y
                        initialTouchX = event.rawX; initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        panelParams.x = initialX + (event.rawX - initialTouchX).toInt()
                        panelParams.y = initialY + (event.rawY - initialTouchY).toInt()
                        wm.updateViewLayout(panelView, panelParams)
                        return true
                    }
                }
                return false
            }
        })
        wm.addView(panelView, panelParams)
    }

    private fun startForegroundNotification() {
        val channelId = "ff_panel_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "FF Panel", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        startForeground(1, NotificationCompat.Builder(this, channelId).setContentTitle("FF Panel").setContentText("Running").setSmallIcon(android.R.drawable.ic_menu_view).setOngoing(true).build())
    }

    override fun onDestroy() {
        if (::espView.isInitialized) wm.removeView(espView)
        if (::panelView.isInitialized) wm.removeView(panelView)
        DetectionBridge.aimActive = false
        super.onDestroy()
    }
}

class ESPView(ctx: Context) : View(ctx) {
    private val boxPaint = Paint().apply { color = Color.rgb(0, 255, 140); style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true }
    private val fovPaint = Paint().apply { color = Color.argb(80, 255, 255, 255); style = Paint.Style.STROKE; strokeWidth = 2f }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (DetectionBridge.aimActive) canvas.drawCircle(width / 2f, height / 2f, DetectionBridge.fovPx.toFloat(), fovPaint)
        if (!DetectionBridge.showEsp) return
        for (d in DetectionBridge.latest) canvas.drawRect(d.left, d.top, d.right, d.bottom, boxPaint)
        invalidate()
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

        if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        if (!Settings.canDrawOverlays(this)) startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))

        findViewById<Button>(R.id.btnAttach).setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            statusText.text = "فعّل FF Panel في Accessibility"
        }
        findViewById<Button>(R.id.btnStart).setOnClickListener {
            if (!Settings.canDrawOverlays(this)) { statusText.text = "صلاحية overlay مطلوبة"; return@setOnClickListener }
            if (aimSwitch.isChecked && !isAccessibilityEnabled()) { statusText.text = "فعّل FF Panel في Accessibility أول"; return@setOnClickListener }
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) { startForegroundService(cap); startForegroundService(ov) } else { startService(cap); startService(ov) }
        statusText.text = "شغّال"
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val expected = "$packageName/${AimAccessibilityService::class.java.name}"
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }
}
EOF

if [ ! -f "$ROOT/gradlew" ]; then
    if command -v gradle >/dev/null 2>&1; then (cd "$ROOT" && gradle wrapper --gradle-version 8.1)
    else echo "[!] Gradle not found."; fi
fi

echo "[✓] Project ready: $ROOT/"
