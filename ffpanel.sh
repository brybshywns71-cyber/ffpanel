#!/usr/bin/env bash
set -euo pipefail
ROOT="FFPanel"
rm -rf "$ROOT"
mkdir -p "$ROOT/app/src/main/java/com/vanta/crosshair" \
         "$ROOT/app/src/main/res/layout" \
         "$ROOT/app/src/main/res/values"

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
rootProject.name = "Crosshair"
include(":app")
EOF
cat > "$ROOT/gradle.properties" <<'EOF'
android.useAndroidX=true
EOF

cat > "$ROOT/app/build.gradle.kts" <<'EOF'
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.vanta.crosshair"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.vanta.crosshair"
        minSdk = 26; targetSdk = 34
        versionCode = 1; versionName = "2.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
EOF

cat > "$ROOT/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <application
        android:allowBackup="true"
        android:label="FF Crosshair"
        android:theme="@style/Theme.AppCompat.DayNight.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".OverlayService" android:exported="false" />
    </application>
</manifest>
EOF

cat > "$ROOT/app/src/main/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical" android:padding="32dp" android:gravity="center"
    android:layout_width="match_parent" android:layout_height="match_parent">
    <TextView android:text="Crosshair & FOV" android:textSize="24sp" android:textStyle="bold" android:layout_marginBottom="24dp"
        android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    <Button android:id="@+id/btnStart" android:text="Start Overlay" android:textSize="18sp"
        android:layout_width="match_parent" android:layout_height="60dp"/>
</LinearLayout>
EOF

cat > "$ROOT/app/src/main/java/com/vanta/crosshair/MainActivity.kt" <<'EOF'
package com.vanta.crosshair

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        findViewById<Button>(R.id.btnStart).setOnClickListener {
            if (!Settings.canDrawOverlays(this)) {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            } else {
                startService(Intent(this, OverlayService::class.java))
                finish()
            }
        }
    }
}
EOF

cat > "$ROOT/app/src/main/java/com/vanta/crosshair/OverlayService.kt" <<'EOF'
package com.vanta.crosshair

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.View
import android.view.WindowManager

class OverlayService : Service() {
    private lateinit var wm: WindowManager
    private lateinit var view: CrosshairView

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        view = CrosshairView(this)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        wm.addView(view, params)
        return START_STICKY
    }

    override fun onDestroy() {
        if (::view.isInitialized) wm.removeView(view)
        super.onDestroy()
    }
}

class CrosshairView(ctx: Context) : View(ctx) {
    private val paint = Paint().apply {
        color = Color.RED
        style = Paint.Style.STROKE
        strokeWidth = 5f
        isAntiAlias = true
    }
    
    private val circlePaint = Paint().apply {
        color = Color.argb(100, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = 3f
        isAntiAlias = true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val size = 30f

        // رسم علامة التصويب (Crosshair)
        canvas.drawLine(cx - size, cy, cx + size, cy, paint) // الخط الأفقي
        canvas.drawLine(cx, cy - size, cx, cy + size, paint) // الخط العمودي
        
        // رسم دايرة الـ FOV
        canvas.drawCircle(cx, cy, 150f, circlePaint)
        
        invalidate() // تحديث مستمر
    }
}
EOF

echo "[✓] Project ready: $ROOT/"
