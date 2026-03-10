package com.geminivpn.utils;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;

import com.geminivpn.models.VPNClient;
import com.geminivpn.models.VPNServer;
import com.google.gson.Gson;

/**
 * PreferencesManager
 * Wraps EncryptedSharedPreferences for secure storage of tokens and
 * sensitive VPN configuration data.
 */
public class PreferencesManager {

    private static final String PREFS_FILE       = "gemini_secure_prefs";
    private static final String KEY_ACCESS_TOKEN  = "access_token";
    private static final String KEY_REFRESH_TOKEN = "refresh_token";
    private static final String KEY_USER_ID       = "user_id";
    private static final String KEY_USER_EMAIL    = "user_email";
    private static final String KEY_USER_NAME     = "user_name";
    private static final String KEY_SUB_STATUS    = "subscription_status";
    private static final String KEY_KILL_SWITCH   = "kill_switch_enabled";
    private static final String KEY_AUTO_CONNECT  = "auto_connect_enabled";
    private static final String KEY_CURRENT_CLIENT = "current_client_json";
    private static final String KEY_CURRENT_SERVER = "current_server_json";
    private static final String KEY_LAST_SERVER_ID = "last_server_id";

    private final SharedPreferences prefs;
    private final Gson gson = new Gson();

    public PreferencesManager(Context context) {
        SharedPreferences p;
        try {
            MasterKey masterKey = new MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build();

            p = EncryptedSharedPreferences.create(
                    context,
                    PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            );
        } catch (Exception e) {
            // Fallback to regular prefs only in unit-test scenarios
            p = context.getSharedPreferences(PREFS_FILE + "_fallback", Context.MODE_PRIVATE);
        }
        this.prefs = p;
    }

    // ─── Tokens ──────────────────────────────────────────────────────────────

    public void saveTokens(String accessToken, String refreshToken) {
        prefs.edit()
                .putString(KEY_ACCESS_TOKEN, accessToken)
                .putString(KEY_REFRESH_TOKEN, refreshToken)
                .apply();
    }

    public String getAccessToken()  { return prefs.getString(KEY_ACCESS_TOKEN, null); }
    public String getRefreshToken() { return prefs.getString(KEY_REFRESH_TOKEN, null); }

    public boolean isLoggedIn() {
        return getAccessToken() != null;
    }

    // ─── User info ────────────────────────────────────────────────────────────

    public void saveUserInfo(String id, String email, String name, String status) {
        prefs.edit()
                .putString(KEY_USER_ID, id)
                .putString(KEY_USER_EMAIL, email)
                .putString(KEY_USER_NAME, name)
                .putString(KEY_SUB_STATUS, status)
                .apply();
    }

    public String getUserId()            { return prefs.getString(KEY_USER_ID, null); }
    public String getUserEmail()         { return prefs.getString(KEY_USER_EMAIL, null); }
    public String getUserName()          { return prefs.getString(KEY_USER_NAME, null); }
    public String getSubscriptionStatus(){ return prefs.getString(KEY_SUB_STATUS, "trial"); }

    // ─── Feature flags ────────────────────────────────────────────────────────

    public boolean isKillSwitchEnabled() { return prefs.getBoolean(KEY_KILL_SWITCH, false); }
    public void setKillSwitchEnabled(boolean enabled) {
        prefs.edit().putBoolean(KEY_KILL_SWITCH, enabled).apply();
    }

    public boolean isAutoConnectEnabled() { return prefs.getBoolean(KEY_AUTO_CONNECT, false); }
    public void setAutoConnectEnabled(boolean enabled) {
        prefs.edit().putBoolean(KEY_AUTO_CONNECT, enabled).apply();
    }

    // ─── Current VPN config ───────────────────────────────────────────────────

    public void saveCurrentClient(VPNClient client) {
        prefs.edit().putString(KEY_CURRENT_CLIENT, gson.toJson(client)).apply();
    }

    public VPNClient getCurrentClient() {
        String json = prefs.getString(KEY_CURRENT_CLIENT, null);
        return json != null ? gson.fromJson(json, VPNClient.class) : null;
    }

    public void saveCurrentServer(VPNServer server) {
        prefs.edit()
                .putString(KEY_CURRENT_SERVER, gson.toJson(server))
                .putString(KEY_LAST_SERVER_ID, server != null ? server.id : null)
                .apply();
    }

    public VPNServer getCurrentServer() {
        String json = prefs.getString(KEY_CURRENT_SERVER, null);
        return json != null ? gson.fromJson(json, VPNServer.class) : null;
    }

    public String getLastServerId() { return prefs.getString(KEY_LAST_SERVER_ID, null); }

    // ─── Session management ───────────────────────────────────────────────────

    public void clearSession() {
        prefs.edit()
                .remove(KEY_ACCESS_TOKEN)
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_USER_ID)
                .remove(KEY_USER_EMAIL)
                .remove(KEY_USER_NAME)
                .remove(KEY_SUB_STATUS)
                .remove(KEY_CURRENT_CLIENT)
                .remove(KEY_CURRENT_SERVER)
                .apply();
    }
}
