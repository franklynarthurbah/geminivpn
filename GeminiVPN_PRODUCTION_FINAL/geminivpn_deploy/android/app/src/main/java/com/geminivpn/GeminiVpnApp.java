package com.geminivpn;

import android.app.Application;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;
import com.geminivpn.utils.PreferencesManager;

public class GeminiVpnApp extends Application {
    public static final String NOTIF_CHANNEL_VPN = "gemini_vpn_service";
    public static final String NOTIF_CHANNEL_KS  = "gemini_kill_switch";
    private static GeminiVpnApp instance;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createNotificationChannels();
    }

    public static GeminiVpnApp getInstance() { return instance; }

    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            NotificationChannel vpnCh = new NotificationChannel(
                NOTIF_CHANNEL_VPN, getString(R.string.notif_channel_name),
                NotificationManager.IMPORTANCE_LOW);
            vpnCh.setDescription(getString(R.string.notif_channel_desc));
            vpnCh.setShowBadge(false);
            nm.createNotificationChannel(vpnCh);
            NotificationChannel ksCh = new NotificationChannel(
                NOTIF_CHANNEL_KS, "Kill Switch", NotificationManager.IMPORTANCE_HIGH);
            nm.createNotificationChannel(ksCh);
        }
    }
}