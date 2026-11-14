package com.gabs.popofferbin;

import android.Manifest;
import android.content.ClipData;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.activity.result.ActivityResultLauncher;
import androidx.appcompat.app.AppCompatActivity;

import com.journeyapps.barcodescanner.ScanContract;
import com.journeyapps.barcodescanner.ScanOptions;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

public class MainActivity extends AppCompatActivity {

    private static final String MIME =
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    private WebView web;

    private final ActivityResultLauncher<ScanOptions> scanner =
            registerForActivityResult(new ScanContract(), result -> {
                if (result.getContents() != null && web != null) {
                    web.evaluateJavascript(
                            "window.onNativeScan(" + JSONObject.quote(result.getContents()) + ")", null);
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (Build.VERSION.SDK_INT < 29
                && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, 1);
        }

        web = new WebView(this);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);

        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(), "Android");
        web.loadUrl("file:///android_asset/index.html");
    }

    /** Simpan ke folder Download. Android 10+ mengembalikan Uri, di bawahnya null. */
    private Uri writeToDownloads(String name, byte[] bytes) throws Exception {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues v = new ContentValues();
            v.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            v.put(MediaStore.MediaColumns.MIME_TYPE, MIME);
            v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (u == null) throw new Exception("gagal membuat file");
            try (OutputStream o = getContentResolver().openOutputStream(u)) {
                o.write(bytes);
            }
            return u;
        }
        File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        dir.mkdirs();
        try (FileOutputStream o = new FileOutputStream(new File(dir, name))) {
            o.write(bytes);
        }
        return null;
    }

    private class Bridge {
        @JavascriptInterface
        public void scan() {
            runOnUiThread(() -> {
                ScanOptions o = new ScanOptions();
                o.setPrompt("Arahkan kamera ke barcode SKU");
                o.setBeepEnabled(true);
                o.setOrientationLocked(false);
                scanner.launch(o);
            });
        }

        @JavascriptInterface
        public String save(String name, String base64) {
            try {
                writeToDownloads(name, Base64.decode(base64, Base64.DEFAULT));
                return "ok";
            } catch (Exception e) {
                return String.valueOf(e.getMessage());
            }
        }

        /** Simpan ke Download lalu langsung buka popup bagikan ke aplikasi lain. */
        @JavascriptInterface
        public String saveShare(String name, String base64) {
            try {
                final Uri uri = writeToDownloads(name, Base64.decode(base64, Base64.DEFAULT));
                if (uri == null) return "ok-saja";
                runOnUiThread(() -> {
                    Intent i = new Intent(Intent.ACTION_SEND);
                    i.setType(MIME);
                    i.putExtra(Intent.EXTRA_STREAM, uri);
                    i.setClipData(ClipData.newRawUri(name, uri));
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    startActivity(Intent.createChooser(i, "Bagikan Excel"));
                });
                return "ok";
            } catch (Exception e) {
                return String.valueOf(e.getMessage());
            }
        }
    }
}
