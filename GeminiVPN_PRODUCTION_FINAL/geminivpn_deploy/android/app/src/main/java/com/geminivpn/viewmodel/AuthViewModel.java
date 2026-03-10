package com.geminivpn.viewmodel;

import android.app.Application;
import androidx.annotation.NonNull;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class AuthViewModel extends AndroidViewModel {
    private final MutableLiveData<Models.AuthResponse> authResult = new MutableLiveData<>();
    private final MutableLiveData<String>              authError  = new MutableLiveData<>();
    private final MutableLiveData<Boolean>             isLoading  = new MutableLiveData<>(false);
    private final PreferencesManager prefs;

    public AuthViewModel(@NonNull Application application) {
        super(application);
        prefs = new PreferencesManager(application);
    }

    public void login(String email, String password) {
        isLoading.postValue(true);
        ApiClient.getInstance(getApplication()).getApi()
            .login(new Models.LoginRequest(email, password))
            .enqueue(new Callback<Models.ApiResponse<Models.AuthResponse>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Models.AuthResponse>> call,
                        Response<Models.ApiResponse<Models.AuthResponse>> response) {
                    isLoading.postValue(false);
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        Models.AuthResponse auth = response.body().data;
                        prefs.saveTokens(auth.accessToken, auth.refreshToken);
                        if (auth.user != null) prefs.saveUserInfo(auth.user);
                        authResult.postValue(auth);
                    } else {
                        authError.postValue("Invalid email or password");
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.AuthResponse>> call, Throwable t) {
                    isLoading.postValue(false);
                    authError.postValue("Network error. Please try again.");
                }
            });
    }

    public void logout() {
        ApiClient.getInstance(getApplication()).getApi()
            .logout().enqueue(new Callback<Models.ApiResponse<Void>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Void>> c, Response<Models.ApiResponse<Void>> r) {}
                @Override public void onFailure(Call<Models.ApiResponse<Void>> c, Throwable t) {}
            });
        prefs.clearAll();
    }

    public LiveData<Models.AuthResponse> getAuthResult() { return authResult; }
    public LiveData<String>              getAuthError()  { return authError;  }
    public LiveData<Boolean>             getIsLoading()  { return isLoading;  }
}