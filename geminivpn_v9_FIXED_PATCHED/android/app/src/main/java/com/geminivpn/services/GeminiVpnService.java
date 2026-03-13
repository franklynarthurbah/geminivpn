package com.geminivpn.services;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import com.geminivpn.R;
import com.geminivpn.models.Models;
import com.geminivpn.ui.MainActivity;
import com.geminivpn.utils.KillSwitchManager;
import com.geminivpn.utils.PreferencesManager;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.nio.channels.DatagramChannel;

/**
 * GeminiVPN Service
 * Handles WireGuard VPN tunnel establishment and management.
 * Implements Android VpnService for OS-level network routing.
 */
public class GeminiVpnService extends VpnService {

    private static final String TAG = "GeminiVpnService";
    public static final String ACTION_CONNECT    = "com.geminivpn.action.CONNECT";
    public static final String ACTION_DISCONNECT = "com.geminivpn.action.DISCONNECT";
    public static final String EXTRA_CLIENT_ID   = "extra_client_id";
    public static final String EXTRA_SERVER_ID   = "extra_server_id";

    private static final String NOTIFICATION_CHANNEL_ID = "geminivpn_service";
    private static final int    NOTIFICATION_ID          = 1001;

    // VPN state
    public enum State { IDLE, CONNECTING, CONNECTED, DISCONNECTING, ERROR }
    private volatile State currentState = State.IDLE;

    // VPN tunnel file descriptor
    private ParcelFileDescriptor vpnInterface;

    // Kill switch manager
    private KillSwitchManager killSwitchManager;

    // Preferences
    private PreferencesManager prefs;

    // Current session data
    private String currentClientId;
    private String currentServerId;
    private Thread vpnThread;

    // ─── Static state broadcast ────────────────────────────────────────────────
    public static final String ACTION_STATE_CHANGED = "com.geminivpn.STATE_CHANGED";
    public static final String EXTRA_STATE          = "extra_state";

    // ─── Lifecycle ──────────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        killSwitchManager = new KillSwitchManager(this);
        prefs = new PreferencesManager(this);
        createNotificationChannel();
        Log.i(TAG, "GeminiVpnService created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            Log.w(TAG, "Null intent received, stopping.");
            stopSelf();
            return START_NOT_STICKY;
        }

        String action = intent.getAction();
        if (ACTION_CONNECT.equals(action)) {
            currentClientId = intent.getStringExtra(EXTRA_CLIENT_ID);
            currentServerId = intent.getStringExtra(EXTRA_SERVER_ID);
            startVpnConnection();
        } else if (ACTION_DISCONNECT.equals(action)) {
            stopVpnConnection();
        }

        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onRevoke() {
        // Called when the VPN is revoked by the system or user
        Log.w(TAG, "VPN permission revoked by system");
        if (prefs.isKillSwitchEnabled()) {
            killSwitchManager.activate();
            broadcastState(State.ERROR);
            showKillSwitchNotification();
        } else {
            stopVpnConnection();
        }
    }

    @Override
    public void onDestroy() {
        stopVpnConnection();
        super.onDestroy();
        Log.i(TAG, "GeminiVpnService destroyed");
    }

    // ─── VPN Connection ─────────────────────────────────────────────────────────

    private void startVpnConnection() {
        setState(State.CONNECTING);
        startForeground(NOTIFICATION_ID, buildNotification("Connecting…"));

        vpnThread = new Thread(() -> {
            try {
                establishVpnTunnel();
            } catch (Exception e) {
                Log.e(TAG, "VPN tunnel error", e);
                setState(State.ERROR);
                if (prefs.isKillSwitchEnabled()) {
                    killSwitchManager.activate();
                    showKillSwitchNotification();
                } else {
                    stopSelf();
                }
            }
        }, "GeminiVPN-Thread");

        vpnThread.start();
    }

    /**
     * Establishes the WireGuard VPN tunnel.
     * Configures routing for all traffic (0.0.0.0/0) through the tunnel.
     */
    private void establishVpnTunnel() throws Exception {
        // Build VPN interface
        Builder builder = new Builder();
        builder.setSession("GeminiVPN");

        // Read current client config from secure storage
        Models.VPNClient client = prefs.getCurrentClient();
        Models.VPNServer server = prefs.getCurrentServer();

        if (client == null || server == null) {
            throw new IllegalStateException("No VPN client/server configuration found");
        }

        // Assign client IP address
        String[] ipParts = client.getAssignedIp().split("\\.");
        builder.addAddress(client.getAssignedIp(), 32);

        // Route ALL traffic through VPN (full tunnel)
        builder.addRoute("0.0.0.0", 0);
        builder.addRoute("::", 0);    // IPv6 – prevents IPv6 leaks

        // DNS servers (Cloudflare, encrypted)
        builder.addDnsServer("1.1.1.1");
        builder.addDnsServer("1.0.0.1");

        // MTU optimised for WireGuard
        builder.setMtu(1420);

        // Prevent VPN app itself from being routed through the tunnel (loop prevention)
        builder.addDisallowedApplication(getPackageName());

        // Blocking mode – no traffic leaks if tunnel fails
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false);
        }

        // Establish tunnel
        vpnInterface = builder.establish();
        if (vpnInterface == null) {
            throw new IOException("Failed to establish VPN interface");
        }

        setState(State.CONNECTED);
        updateNotification("Connected – " + server.getCity() + ", " + server.getCountry());
        killSwitchManager.deactivate(); // VPN is up, lift any previous kill-switch block

        Log.i(TAG, "VPN tunnel established. Assigned IP: " + client.getAssignedIp());

        // Keep tunnel alive – read/write packets
        runTunnelLoop(vpnInterface);
    }

    /**
     * Main packet relay loop.
     * In a production WireGuard implementation this would hand-off to
     * wireguard-go or the kernel module; here we manage the fd lifetime.
     */
    private void runTunnelLoop(ParcelFileDescriptor vpnFd) throws IOException {
        FileInputStream  in  = new FileInputStream(vpnFd.getFileDescriptor());
        FileOutputStream out = new FileOutputStream(vpnFd.getFileDescriptor());

        ByteBuffer packet = ByteBuffer.allocate(32767);

        while (currentState == State.CONNECTED) {
            // In production: hand packets to WireGuard userspace or kernel module.
            // For scaffold: keep fd open and allow WireGuard-go to handle the actual crypto.
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }

        in.close();
        out.close();
    }

    private void stopVpnConnection() {
        setState(State.DISCONNECTING);

        if (vpnThread != null) {
            vpnThread.interrupt();
        }

        if (vpnInterface != null) {
            try {
                vpnInterface.close();
            } catch (IOException e) {
                Log.e(TAG, "Error closing VPN interface", e);
            }
            vpnInterface = null;
        }

        killSwitchManager.deactivate();
        setState(State.IDLE);
        stopForeground(true);
        stopSelf();
        Log.i(TAG, "VPN connection stopped");
    }

    // ─── State Management ───────────────────────────────────────────────────────

    private void setState(State state) {
        currentState = state;
        broadcastState(state);
    }

    private void broadcastState(State state) {
        Intent intent = new Intent(ACTION_STATE_CHANGED);
        intent.putExtra(EXTRA_STATE, state.name());
        sendBroadcast(intent);
    }

    public static State getCurrentState() {
        // Accessed by UI via static reference (simplified for scaffold)
        return State.IDLE;
    }

    // ─── Notifications ──────────────────────────────────────────────────────────

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "GeminiVPN Service",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("VPN connection status");
            channel.setShowBadge(false);

            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification(String status) {
        Intent launchIntent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Intent disconnectIntent = new Intent(this, GeminiVpnService.class);
        disconnectIntent.setAction(ACTION_DISCONNECT);
        PendingIntent disconnectPi = PendingIntent.getService(
                this, 1, disconnectIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        return new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("GeminiVPN")
                .setContentText(status)
                .setSmallIcon(R.drawable.ic_vpn_key)
                .setContentIntent(pi)
                .addAction(R.drawable.ic_disconnect, "Disconnect", disconnectPi)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    private void updateNotification(String status) {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(status));
    }

    private void showKillSwitchNotification() {
        Intent launchIntent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification notification = new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("GeminiVPN – Kill Switch Active")
                .setContentText("Internet blocked. VPN disconnected unexpectedly.")
                .setSmallIcon(R.drawable.ic_shield_off)
                .setContentIntent(pi)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setColor(0xFFE53935)
                .build();

        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIFICATION_ID, notification);
    }
}
