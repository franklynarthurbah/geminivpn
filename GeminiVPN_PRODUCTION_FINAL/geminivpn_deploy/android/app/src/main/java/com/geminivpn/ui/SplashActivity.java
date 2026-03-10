package com.geminivpn.ui;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import androidx.appcompat.app.AppCompatActivity;
import com.geminivpn.R;
import com.geminivpn.utils.PreferencesManager;

public class SplashActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_splash);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            PreferencesManager prefs = new PreferencesManager(this);
            Intent intent = prefs.getAccessToken() != null
                ? new Intent(this, MainActivity.class)
                : new Intent(this, LoginActivity.class);
            startActivity(intent);
            finish();
        }, 1200);
    }
}