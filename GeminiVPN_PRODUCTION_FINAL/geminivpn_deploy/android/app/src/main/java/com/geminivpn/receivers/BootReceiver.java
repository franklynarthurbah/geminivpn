package com.geminivpn.receivers;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction()) &&
            !"android.intent.action.QUICKBOOT_POWERON".equals(intent.getAction())) return;
        PreferencesManager prefs = new PreferencesManager(context);
        if (prefs.isAutoConnectEnabled() && prefs.getAccessToken() != null) {
            Intent vpnIntent = new Intent(context, GeminiVpnService.class);
            vpnIntent.setAction(GeminiVpnService.ACTION_CONNECT);
            context.startForegroundService(vpnIntent);
        }
    }
}