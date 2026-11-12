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

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import com.google.zxing.integration.android.IntentIntegrator;
import com.google.zxing.integration.android.IntentResult;
import java.io.OutputStream;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private WebView web;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());
        web.addJavascriptInterface(new Bridge(), "Android");
        web.loadUrl("file:///android_asset/index.html");
    }

    class Bridge {
        @JavascriptInterface
        public void scan() {
            runOnUiThread(new Runnable() {
                public void run() {
                    new IntentIntegrator(MainActivity.this)
                        .setPrompt("Arahkan ke barcode SKU")
                        .setBeepEnabled(false)
                        .setOrientationLocked(false)
                        .initiateScan();
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

    @Override
    protected void onActivityResult(int rq, int rs, Intent d) {
        IntentResult r = IntentIntegrator.parseActivityResult(rq, rs, d);
        if (r != null) {
            if (r.getContents() != null) {
                web.evaluateJavascript("window.onNativeScan(" + JSONObject.quote(r.getContents()) + ")", null);
            }
        } else {
            super.onActivityResult(rq, rs, d);
        }
    }
}
EOF

gradle assembleDebug --no-daemon --stacktrace
