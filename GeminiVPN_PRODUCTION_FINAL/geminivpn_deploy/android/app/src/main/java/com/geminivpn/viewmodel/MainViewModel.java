package com.geminivpn.viewmodel;

import android.app.Application;
import androidx.annotation.NonNull;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import java.util.List;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class MainViewModel extends AndroidViewModel {
    private final MutableLiveData<List<Models.VPNServer>> servers  = new MutableLiveData<>();
    private final MutableLiveData<List<Models.VPNClient>> clients  = new MutableLiveData<>();
    private final MutableLiveData<Models.UserProfile>     profile  = new MutableLiveData<>();
    private final MutableLiveData<String>                 error    = new MutableLiveData<>();
    private final PreferencesManager prefs;

    public MainViewModel(@NonNull Application application) {
        super(application);
        prefs = new PreferencesManager(application);
        loadData();
    }

    public void loadData() { loadServers(); loadClients(); loadProfile(); }

    public void loadServers() {
        ApiClient.getInstance(getApplication()).getApi().getServers()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNServer>>>() {
                @Override public void onResponse(Call<Models.ApiResponse<List<Models.VPNServer>>> call,
                        Response<Models.ApiResponse<List<Models.VPNServer>>> response) {
                    if (response.isSuccessful() && response.body() != null)
                        servers.postValue(response.body().data);
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNServer>>> call, Throwable t) {
                    error.postValue(t.getMessage());
                }
            });
    }

    public void loadClients() {
        ApiClient.getInstance(getApplication()).getApi().getClients()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNClient>>>() {
                @Override public void onResponse(Call<Models.ApiResponse<List<Models.VPNClient>>> call,
                        Response<Models.ApiResponse<List<Models.VPNClient>>> response) {
                    if (response.isSuccessful() && response.body() != null)
                        clients.postValue(response.body().data);
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNClient>>> call, Throwable t) {}
            });
    }

    public void loadProfile() {
        ApiClient.getInstance(getApplication()).getApi().getProfile()
            .enqueue(new Callback<Models.ApiResponse<Models.UserProfile>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Models.UserProfile>> call,
                        Response<Models.ApiResponse<Models.UserProfile>> response) {
                    if (response.isSuccessful() && response.body() != null)
                        profile.postValue(response.body().data);
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.UserProfile>> call, Throwable t) {}
            });
    }

    public LiveData<List<Models.VPNServer>> getServers() { return servers; }
    public LiveData<List<Models.VPNClient>> getClients() { return clients; }
    public LiveData<Models.UserProfile>     getProfile() { return profile; }
    public LiveData<String>                 getError()   { return error;   }
}