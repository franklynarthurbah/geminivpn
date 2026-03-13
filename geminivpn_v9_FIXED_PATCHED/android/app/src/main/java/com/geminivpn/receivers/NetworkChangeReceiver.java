package com.geminivpn.receivers;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;

/**
 * NetworkChangeReceiver
 * Triggers VPN reconnect when network is restored (WiFi ↔ Mobile switch).
 * FIX: replaced deprecated getActiveNetworkInfo() (crashes API 29+)
 *      with NetworkCapabilities API (works API 26+).
 */
public class NetworkChangeReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!isConnected(context)) return;

        PreferencesManager prefs = new PreferencesManager(context);
        if (prefs.isAutoConnectEnabled() && prefs.getAccessToken() != null) {
            // Network is back — trigger VPN reconnect
            Intent vpnIntent = new Intent(context, GeminiVpnService.class);
            vpnIntent.setAction(GeminiVpnService.ACTION_CONNECT);
            context.startForegroundService(vpnIntent);
        }
    }

    private boolean isConnected(Context context) {
        ConnectivityManager cm =
                (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) return false;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // API 23+ — use NetworkCapabilities (non-deprecated)
            Network network = cm.getActiveNetwork();
            if (network == null) return false;
            NetworkCapabilities caps = cm.getNetworkCapabilities(network);
            return caps != null && (
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                    || caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                    || caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            );
        } else {
            // API 21–22 fallback (minSdk is 26 so this branch is never reached,
            // but kept for safety and clarity)
            android.net.NetworkInfo info = cm.getActiveNetworkInfo();
            return info != null && info.isConnected();
        }
    }
}
