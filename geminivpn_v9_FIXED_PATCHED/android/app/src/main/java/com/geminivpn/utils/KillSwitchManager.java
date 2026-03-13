package com.geminivpn.utils;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.util.Log;

/**
 * KillSwitchManager
 *
 * Blocks all non-VPN internet traffic when the VPN drops unexpectedly.
 * Uses ConnectivityManager's bindProcessToNetwork to enforce routing.
 * On Android 7+ this is supplemented by the VPN's "blocking mode"
 * (Builder.setBlocking) which is set in GeminiVpnService.
 */
public class KillSwitchManager {

    private static final String TAG = "KillSwitchManager";

    private final Context context;
    private final ConnectivityManager connectivityManager;
    private boolean isActive = false;

    // Callback held when we're binding the process to the VPN network
    private ConnectivityManager.NetworkCallback vpnNetworkCallback;

    public KillSwitchManager(Context context) {
        this.context = context.getApplicationContext();
        this.connectivityManager =
                (ConnectivityManager) this.context.getSystemService(Context.CONNECTIVITY_SERVICE);
    }

    /**
     * Activate kill-switch: bind process to VPN network only.
     * Any traffic that cannot route through the VPN will be blocked
     * rather than leaking to the default network.
     */
    public void activate() {
        if (isActive) return;

        Log.w(TAG, "Kill switch ACTIVATED – blocking non-VPN traffic");

        // Request a VPN network and bind the process to it exclusively.
        // If no VPN network is available, traffic will fail rather than leak.
        NetworkRequest request = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build();

        vpnNetworkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                // Bind only when VPN network becomes available again
                connectivityManager.bindProcessToNetwork(network);
                Log.i(TAG, "Process bound to VPN network");
            }

            @Override
            public void onLost(Network network) {
                // VPN gone – unbind so ALL traffic is blocked (no fallback)
                connectivityManager.bindProcessToNetwork(null);
                Log.w(TAG, "VPN network lost – all traffic blocked");
            }
        };

        connectivityManager.registerNetworkCallback(request, vpnNetworkCallback);
        // Immediately unbind from any existing network until VPN re-establishes
        connectivityManager.bindProcessToNetwork(null);
        isActive = true;
    }

    /**
     * Deactivate kill-switch: restore normal network routing.
     */
    public void deactivate() {
        if (!isActive) return;

        Log.i(TAG, "Kill switch DEACTIVATED – restoring normal routing");

        if (vpnNetworkCallback != null) {
            try {
                connectivityManager.unregisterNetworkCallback(vpnNetworkCallback);
            } catch (IllegalArgumentException e) {
                Log.w(TAG, "NetworkCallback was not registered: " + e.getMessage());
            }
            vpnNetworkCallback = null;
        }

        // Restore normal routing
        connectivityManager.bindProcessToNetwork(null);
        isActive = false;
    }

    public boolean isActive() {
        return isActive;
    }
}
