#!/bin/bash
# Menyusun proyek Android dari index.html + icon.png, lalu membuild APK.
set -euo pipefail
mkdir -p src/main/java/com/gabs/popofferbin src/main/assets src/main/res/values src/main/res/drawable-nodpi src/main/res/mipmap-anydpi-v26

cp index.html src/main/assets/index.html
cp icon.png src/main/res/drawable-nodpi/ic_fg.png
curl -fsSL -o src/main/assets/exceljs.min.js https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js
sed -i 's#https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js#exceljs.min.js#' src/main/assets/index.html

cat > gradle.properties << 'EOF'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2g
EOF

cat > settings.gradle << 'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "POPOFFERBIN"
EOF

cat > build.gradle << 'EOF'
plugins { id 'com.android.application' version '8.5.2' }
android {
    namespace 'com.gabs.popofferbin'
    compileSdk 34
    defaultConfig {
        applicationId 'com.gabs.popofferbin'
        minSdk 29
        targetSdk 34
        versionCode 1
        versionName '1.0'
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
dependencies {
    implementation 'com.journeyapps:zxing-android-embedded:4.3.0'
}
EOF

cat > src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <application
        android:label="POP OFFERBIN"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:allowBackup="true"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|smallestScreenSize|uiMode">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > src/main/res/values/colors.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_bg">#FDA868</color>
</resources>
EOF

cat > src/main/res/mipmap-anydpi-v26/ic_launcher.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_bg"/>
    <foreground>
        <inset android:drawable="@drawable/ic_fg" android:inset="14%"/>
    </foreground>
</adaptive-icon>
EOF

cat > src/main/java/com/gabs/popofferbin/MainActivity.java << 'EOF'
package com.gabs.popofferbin;

import android.Manifest;
import android.app.Activity;
import android.content.ContentValues;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.Gravity;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.ResultPoint;
import com.journeyapps.barcodescanner.BarcodeCallback;
import com.journeyapps.barcodescanner.BarcodeResult;
import com.journeyapps.barcodescanner.DecoratedBarcodeView;
import com.journeyapps.barcodescanner.DefaultDecoderFactory;
import com.journeyapps.barcodescanner.camera.CameraSettings;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.List;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private WebView web;
    private LinearLayout panel, frame;
    private DecoratedBarcodeView scanView;
    private boolean scanOpen = false, gotResult = false;

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    private void js(String code) {
        web.evaluateJavascript(code, null);
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        FrameLayout root = new FrameLayout(this);
        web = new WebView(this);
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));
        buildPanel(root);
        setContentView(root);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());
        web.addJavascriptInterface(new Bridge(), "Android");
        web.loadUrl("file:///android_asset/index.html");
    }

    /* Jendela kamera scanner di dalam aplikasi (tanpa Activity lain) */
    private void buildPanel(FrameLayout root) {
        panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setBackgroundColor(Color.BLACK);
        panel.setPadding(dp(12), dp(12), dp(12), dp(12));
        panel.setVisibility(View.GONE);

        TextView t = new TextView(this);
        t.setText("Arahkan kamera ke barcode SKU");
        t.setTextColor(Color.WHITE);
        t.setTextSize(15);
        t.setGravity(Gravity.CENTER);
        panel.addView(t, new LinearLayout.LayoutParams(-1, -2));

        frame = new LinearLayout(this);
        frame.setPadding(dp(5), dp(5), dp(5), dp(5));
        frame.setBackgroundColor(0xFF2A2A2A);
        scanView = new DecoratedBarcodeView(this);
        scanView.setStatusText("");
        scanView.getBarcodeView().setDecoderFactory(new DefaultDecoderFactory(Arrays.asList(
            BarcodeFormat.EAN_13, BarcodeFormat.EAN_8, BarcodeFormat.UPC_A, BarcodeFormat.UPC_E,
            BarcodeFormat.CODE_128, BarcodeFormat.CODE_39, BarcodeFormat.CODE_93,
            BarcodeFormat.ITF, BarcodeFormat.CODABAR, BarcodeFormat.QR_CODE, BarcodeFormat.DATA_MATRIX)));
        CameraSettings cs = scanView.getBarcodeView().getCameraSettings();
        cs.setContinuousFocusEnabled(true);
        cs.setBarcodeSceneModeEnabled(true);
        scanView.getBarcodeView().setCameraSettings(cs);
        frame.addView(scanView, new LinearLayout.LayoutParams(-1, -1));
        LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(-1, 0, 1f);
        fp.topMargin = dp(10);
        fp.bottomMargin = dp(10);
        panel.addView(frame, fp);

        TextView close = new TextView(this);
        close.setText("Tutup");
        close.setTextSize(16);
        close.setTypeface(null, Typeface.BOLD);
        close.setTextColor(0xFF00262C);
        close.setGravity(Gravity.CENTER);
        GradientDrawable g = new GradientDrawable();
        g.setColor(0xFF22D3EE);
        g.setCornerRadius(dp(14));
        close.setBackground(g);
        close.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                closeScan();
            }
        });
        panel.addView(close, new LinearLayout.LayoutParams(-1, dp(48)));

        int h = (int) (getResources().getDisplayMetrics().heightPixels * 0.6);
        root.addView(panel, new FrameLayout.LayoutParams(-1, h, Gravity.TOP));
    }

    private void openScan() {
        gotResult = false;
        frame.setBackgroundColor(0xFF2A2A2A);
        panel.setVisibility(View.VISIBLE);
        scanOpen = true;
        scanView.decodeContinuous(new BarcodeCallback() {
            public void barcodeResult(BarcodeResult r) {
                if (gotResult || r == null || r.getText() == null) return;
                gotResult = true;
                frame.setBackgroundColor(0xFF22C55E);
                try {
                    new ToneGenerator(AudioManager.STREAM_MUSIC, 100).startTone(ToneGenerator.TONE_PROP_BEEP, 150);
                } catch (Exception e) { }
                js("window.onNativeScan(" + JSONObject.quote(r.getText()) + ")");
                panel.postDelayed(new Runnable() {
                    public void run() {
                        closeScan();
                    }
                }, 400);
            }

            public void possibleResultPoints(List<ResultPoint> points) { }
        });
        scanView.resume();
    }

    private void closeScan() {
        scanOpen = false;
        scanView.pause();
        panel.setVisibility(View.GONE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (scanOpen) scanView.resume();
    }

    @Override
    protected void onPause() {
        super.onPause();
        scanView.pause();
    }

    @Override
    public void onBackPressed() {
        if (scanOpen) closeScan();
        else super.onBackPressed();
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] res) {
        super.onRequestPermissionsResult(code, perms, res);
        if (code == 77) {
            if (res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED) openScan();
            else js("toast('Izin kamera ditolak')");
        }
    }

    class Bridge {
        @JavascriptInterface
        public void scan() {
            runOnUiThread(new Runnable() {
                public void run() {
                    try {
                        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) openScan();
                        else requestPermissions(new String[]{Manifest.permission.CAMERA}, 77);
                    } catch (Exception e) {
                        js("toast('Kamera gagal dibuka')");
                    }
                }
            });
        }

        @JavascriptInterface
        public String save(String name, String b64) {
            try {
                byte[] bytes = Base64.decode(b64, Base64.DEFAULT);
                ContentValues v = new ContentValues();
                v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                v.put(MediaStore.Downloads.MIME_TYPE, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
                v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                OutputStream o = getContentResolver().openOutputStream(u);
                o.write(bytes);
                o.close();
                return "ok";
            } catch (Exception e) {
                return String.valueOf(e.getMessage());
            }
        }
    }
}
EOF

gradle assembleDebug --no-daemon --stacktrace
