package com.geminivpn.receivers;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;

public class NetworkChangeReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo info = cm.getActiveNetworkInfo();
        boolean connected = info != null && info.isConnected();
        if (connected) {
            PreferencesManager prefs = new PreferencesManager(context);
            if (prefs.isAutoConnectEnabled() && prefs.getAccessToken() != null) {
                // Trigger reconnect if network restored
                Intent vpnIntent = new Intent(context, GeminiVpnService.class);
                vpnIntent.setAction(GeminiVpnService.ACTION_CONNECT);
                context.startForegroundService(vpnIntent);
            }
        }
    }
}