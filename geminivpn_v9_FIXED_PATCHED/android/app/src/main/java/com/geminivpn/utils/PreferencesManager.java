package com.geminivpn.utils;

import android.content.Context;
import android.content.SharedPreferences;
import com.google.gson.Gson;
import com.geminivpn.models.Models;

public class PreferencesManager {

    private static final String PREFS_NAME     = "geminivpn_prefs";
    private static final String KEY_ACCESS_TOKEN  = "access_token";
    private static final String KEY_REFRESH_TOKEN = "refresh_token";
    private static final String KEY_USER_EMAIL    = "user_email";
    private static final String KEY_USER_NAME     = "user_name";
    private static final String KEY_KILL_SWITCH   = "kill_switch_enabled";
    private static final String KEY_AUTO_CONNECT  = "auto_connect_enabled";
    private static final String KEY_CURRENT_SERVER= "current_server_json";
    private static final String KEY_CURRENT_CLIENT= "current_client_json";
    private static final String KEY_SELECTED_SRV_ID = "selected_server_id";

    private final SharedPreferences prefs;
    private final Gson gson = new Gson();

    public PreferencesManager(Context context) {
        prefs = context.getApplicationContext()
                       .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // ─── Tokens ──────────────────────────────────────────────────────────────
    public void saveTokens(String access, String refresh) {
        prefs.edit().putString(KEY_ACCESS_TOKEN, access)
                    .putString(KEY_REFRESH_TOKEN, refresh).apply();
    }
    public String  getAccessToken()  { return prefs.getString(KEY_ACCESS_TOKEN,  null); }
    public String  getRefreshToken() { return prefs.getString(KEY_REFRESH_TOKEN, null); }
    public boolean isLoggedIn()      { return getAccessToken() != null; }

    public void clearSession() {
        prefs.edit().remove(KEY_ACCESS_TOKEN).remove(KEY_REFRESH_TOKEN)
                    .remove(KEY_USER_EMAIL).remove(KEY_USER_NAME).apply();
    }

    // ─── User ────────────────────────────────────────────────────────────────
    public void saveUserProfile(String email, String name) {
        prefs.edit().putString(KEY_USER_EMAIL, email)
                    .putString(KEY_USER_NAME,  name).apply();
    }
    public String getUserEmail() { return prefs.getString(KEY_USER_EMAIL, ""); }
    public String getUserName()  { return prefs.getString(KEY_USER_NAME,  ""); }

    // ─── Kill switch ─────────────────────────────────────────────────────────
    public boolean isKillSwitchEnabled()               { return prefs.getBoolean(KEY_KILL_SWITCH, false); }
    public void    setKillSwitchEnabled(boolean enabled) { prefs.edit().putBoolean(KEY_KILL_SWITCH, enabled).apply(); }

    // ─── Auto-connect ─────────────────────────────────────────────────────────
    public boolean isAutoConnectEnabled()              { return prefs.getBoolean(KEY_AUTO_CONNECT, false); }
    public void    setAutoConnectEnabled(boolean enabled){ prefs.edit().putBoolean(KEY_AUTO_CONNECT, enabled).apply(); }

    // ─── Current server/client (JSON-serialized) ─────────────────────────────
    public void saveCurrentServer(Models.VPNServer server) {
        prefs.edit().putString(KEY_CURRENT_SERVER, gson.toJson(server))
                    .putString(KEY_SELECTED_SRV_ID, server != null ? server.id : null).apply();
    }
    public Models.VPNServer getCurrentServer() {
        String json = prefs.getString(KEY_CURRENT_SERVER, null);
        return json != null ? gson.fromJson(json, Models.VPNServer.class) : null;
    }
    public String getSelectedServerId() { return prefs.getString(KEY_SELECTED_SRV_ID, null); }

    public void saveCurrentClient(Models.VPNClient client) {
        prefs.edit().putString(KEY_CURRENT_CLIENT, gson.toJson(client)).apply();
    }
    public Models.VPNClient getCurrentClient() {
        String json = prefs.getString(KEY_CURRENT_CLIENT, null);
        return json != null ? gson.fromJson(json, Models.VPNClient.class) : null;
    }
}
