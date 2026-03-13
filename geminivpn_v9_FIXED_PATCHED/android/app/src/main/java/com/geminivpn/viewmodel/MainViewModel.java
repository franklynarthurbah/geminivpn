package com.geminivpn.viewmodel;

import android.app.Application;
import android.content.Context;
import androidx.annotation.NonNull;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;
import java.util.List;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class MainViewModel extends AndroidViewModel {

    private final MutableLiveData<List<Models.VPNServer>> servers      = new MutableLiveData<>();
    private final MutableLiveData<List<Models.VPNClient>> clients      = new MutableLiveData<>();
    private final MutableLiveData<Models.UserProfile>     profile      = new MutableLiveData<>();
    private final MutableLiveData<String>                 errorMessage = new MutableLiveData<>();
    private final MutableLiveData<Models.VPNServer>       selectedServer = new MutableLiveData<>();
    private final MutableLiveData<Models.VPNClient>       activeClient   = new MutableLiveData<>();

    private volatile GeminiVpnService.State currentState = GeminiVpnService.State.IDLE;
    private final PreferencesManager prefs;

    public MainViewModel(@NonNull Application application) {
        super(application);
        prefs = new PreferencesManager(application);
    }

    public void loadData(Context ctx) {
        loadServers(ctx);
        loadClients(ctx);
        loadProfile(ctx);
    }

    public void loadServers(Context ctx) {
        ApiClient.getInstance(ctx).getApi().getServers()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNServer>>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<List<Models.VPNServer>>> call,
                        Response<Models.ApiResponse<List<Models.VPNServer>>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        List<Models.VPNServer> list = response.body().data;
                        servers.postValue(list);
                        if (selectedServer.getValue() == null && !list.isEmpty()) {
                            selectedServer.postValue(list.get(0));
                        }
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNServer>>> call, Throwable t) {
                    errorMessage.postValue("Failed to load servers: " + t.getMessage());
                }
            });
    }

    public void loadClients(Context ctx) {
        ApiClient.getInstance(ctx).getApi().getClients()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNClient>>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<List<Models.VPNClient>>> call,
                        Response<Models.ApiResponse<List<Models.VPNClient>>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        List<Models.VPNClient> list = response.body().data;
                        clients.postValue(list);
                        if (activeClient.getValue() == null && !list.isEmpty()) {
                            for (Models.VPNClient c : list) {
                                if (c.isConnected()) { activeClient.postValue(c); return; }
                            }
                        }
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNClient>>> call, Throwable t) {}
            });
    }

    public void loadProfile(Context ctx) {
        ApiClient.getInstance(ctx).getApi().getProfile()
            .enqueue(new Callback<Models.ApiResponse<Models.UserProfile>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.UserProfile>> call,
                        Response<Models.ApiResponse<Models.UserProfile>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        profile.postValue(response.body().data);
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.UserProfile>> call, Throwable t) {}
            });
    }

    public void createClientAndConnect(Context ctx) {
        Models.VPNServer server = selectedServer.getValue();
        if (server == null) { errorMessage.postValue("Please select a server first"); return; }
        Models.CreateClientRequest req = new Models.CreateClientRequest("Android Device", server.id);
        ApiClient.getInstance(ctx).getApi().createClient(req)
            .enqueue(new Callback<Models.ApiResponse<Models.VPNClient>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.VPNClient>> call,
                        Response<Models.ApiResponse<Models.VPNClient>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        activeClient.postValue(response.body().data);
                    } else {
                        errorMessage.postValue("Failed to create VPN client");
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.VPNClient>> call, Throwable t) {
                    errorMessage.postValue("Network error: " + t.getMessage());
                }
            });
    }

    public void setKillSwitchEnabled(boolean enabled) { prefs.setKillSwitchEnabled(enabled); }

    public GeminiVpnService.State getCurrentState()     { return currentState; }
    public void setCurrentState(GeminiVpnService.State s) { currentState = s; }

    public LiveData<List<Models.VPNServer>> getServers()       { return servers; }
    public LiveData<List<Models.VPNClient>> getClients()       { return clients; }
    public LiveData<Models.UserProfile>     getProfile()       { return profile; }
    public LiveData<String>                 getErrorMessage()  { return errorMessage; }
    public LiveData<Models.VPNServer>       getSelectedServer(){ return selectedServer; }
    public LiveData<Models.VPNClient>       getActiveClient()  { return activeClient; }
    public void setSelectedServer(Models.VPNServer s)         { selectedServer.setValue(s); }
}
