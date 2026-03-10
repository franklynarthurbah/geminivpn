package com.geminivpn.ui;

import android.content.Intent;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.textfield.TextInputEditText;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class RegisterActivity extends AppCompatActivity {
    private TextInputEditText etName, etEmail, etPassword;
    private Button btnRegister;
    private ProgressBar progressBar;
    private PreferencesManager prefs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_register);
        prefs = new PreferencesManager(this);
        etName     = findViewById(R.id.etName);
        etEmail    = findViewById(R.id.etEmail);
        etPassword = findViewById(R.id.etPassword);
        btnRegister = findViewById(R.id.btnRegister);
        progressBar = findViewById(R.id.progressBar);
        TextView tvLogin = findViewById(R.id.tvLogin);
        btnRegister.setOnClickListener(v -> attemptRegister());
        tvLogin.setOnClickListener(v -> finish());
    }

    private void attemptRegister() {
        String name  = etName.getText() != null ? etName.getText().toString().trim() : "";
        String email = etEmail.getText() != null ? etEmail.getText().toString().trim() : "";
        String pass  = etPassword.getText() != null ? etPassword.getText().toString() : "";
        if (TextUtils.isEmpty(name))  { etName.setError(getString(R.string.error_name_required)); return; }
        if (TextUtils.isEmpty(email)) { etEmail.setError(getString(R.string.error_email_required)); return; }
        if (TextUtils.isEmpty(pass))  { etPassword.setError(getString(R.string.error_password_required)); return; }
        setLoading(true);
        ApiClient.getInstance(this).getApi()
            .register(new Models.RegisterRequest(name, email, pass))
            .enqueue(new Callback<Models.ApiResponse<Models.AuthResponse>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Models.AuthResponse>> call,
                        Response<Models.ApiResponse<Models.AuthResponse>> response) {
                    setLoading(false);
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        Models.AuthResponse auth = response.body().data;
                        prefs.saveTokens(auth.accessToken, auth.refreshToken);
                        if (auth.user != null) prefs.saveUserInfo(auth.user);
                        startActivity(new Intent(RegisterActivity.this, MainActivity.class)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
                    } else {
                        Toast.makeText(RegisterActivity.this, "Registration failed", Toast.LENGTH_SHORT).show();
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.AuthResponse>> call, Throwable t) {
                    setLoading(false);
                    Toast.makeText(RegisterActivity.this, getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }

    private void setLoading(boolean loading) {
        btnRegister.setEnabled(!loading);
        progressBar.setVisibility(loading ? View.VISIBLE : View.GONE);
    }
}