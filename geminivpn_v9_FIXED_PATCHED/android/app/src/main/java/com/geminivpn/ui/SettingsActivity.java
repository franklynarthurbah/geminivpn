package com.geminivpn.ui;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.switchmaterial.SwitchMaterial;
import com.geminivpn.R;
import com.geminivpn.utils.PreferencesManager;

public class SettingsActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        PreferencesManager prefs = new PreferencesManager(this);
        findViewById(R.id.btnBack).setOnClickListener(v -> finish());
        SwitchMaterial swKS = findViewById(R.id.switchKillSwitch);
        swKS.setChecked(prefs.isKillSwitchEnabled());
        swKS.setOnCheckedChangeListener((b, isChecked) -> prefs.setKillSwitchEnabled(isChecked));
        SwitchMaterial swAC = findViewById(R.id.switchAutoConnect);
        swAC.setChecked(prefs.isAutoConnectEnabled());
        swAC.setOnCheckedChangeListener((b, isChecked) -> prefs.setAutoConnectEnabled(isChecked));
    }
}