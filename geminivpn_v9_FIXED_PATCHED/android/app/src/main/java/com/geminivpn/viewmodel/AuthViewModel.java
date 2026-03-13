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

    public enum AuthState { IDLE, LOADING, SUCCESS, ERROR }

    private final MutableLiveData<AuthState> state   = new MutableLiveData<>(AuthState.IDLE);
    private final MutableLiveData<String>    message = new MutableLiveData<>();
    private final PreferencesManager prefs;

    public AuthViewModel(@NonNull Application application) {
        super(application);
        prefs = new PreferencesManager(application);
    }

    public void login(String email, String password) {
        state.setValue(AuthState.LOADING);
        ApiClient.getInstance(getApplication()).getApi()
            .login(new Models.LoginRequest(email, password))
            .enqueue(new Callback<Models.ApiResponse<Models.AuthResponse>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.AuthResponse>> call,
                        Response<Models.ApiResponse<Models.AuthResponse>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        Models.AuthResponse auth = response.body().data;
                        prefs.saveTokens(auth.tokens.accessToken, auth.tokens.refreshToken);
                        if (auth.user != null) prefs.saveUserProfile(auth.user.email, auth.user.name);
                        state.postValue(AuthState.SUCCESS);
                    } else {
                        String msg = (response.body() != null) ? response.body().message : "Login failed";
                        message.postValue(msg != null ? msg : "Invalid email or password");
                        state.postValue(AuthState.ERROR);
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.AuthResponse>> call, Throwable t) {
                    message.postValue("Network error: " + t.getMessage());
                    state.postValue(AuthState.ERROR);
                }
            });
    }

    public void register(String email, String password, String name) {
        state.setValue(AuthState.LOADING);
        ApiClient.getInstance(getApplication()).getApi()
            .register(new Models.RegisterRequest(email, password, name))
            .enqueue(new Callback<Models.ApiResponse<Models.AuthResponse>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.AuthResponse>> call,
                        Response<Models.ApiResponse<Models.AuthResponse>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        Models.AuthResponse auth = response.body().data;
                        prefs.saveTokens(auth.tokens.accessToken, auth.tokens.refreshToken);
                        if (auth.user != null) prefs.saveUserProfile(auth.user.email, auth.user.name);
                        state.postValue(AuthState.SUCCESS);
                    } else {
                        String msg = (response.body() != null) ? response.body().message : "Registration failed";
                        message.postValue(msg != null ? msg : "Registration failed");
                        state.postValue(AuthState.ERROR);
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.AuthResponse>> call, Throwable t) {
                    message.postValue("Network error: " + t.getMessage());
                    state.postValue(AuthState.ERROR);
                }
            });
    }

    public LiveData<AuthState> getState()   { return state; }
    public LiveData<String>    getMessage() { return message; }
}
