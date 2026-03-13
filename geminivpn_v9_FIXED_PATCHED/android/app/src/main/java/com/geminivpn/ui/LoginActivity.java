package com.geminivpn.ui;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.lifecycle.ViewModelProvider;
import com.geminivpn.R;
import com.geminivpn.viewmodel.AuthViewModel;

public class LoginActivity extends AppCompatActivity {

    private EditText    etEmail, etPassword;
    private Button      btnLogin;
    private ProgressBar progress;
    private AuthViewModel viewModel;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_login);

        etEmail   = findViewById(R.id.etEmail);
        etPassword= findViewById(R.id.etPassword);
        btnLogin  = findViewById(R.id.btnLogin);
        progress  = findViewById(R.id.progressBar);

        viewModel = new ViewModelProvider(this).get(AuthViewModel.class);

        btnLogin.setOnClickListener(v -> {
            String email = etEmail.getText().toString().trim();
            String pass  = etPassword.getText().toString().trim();
            if (email.isEmpty())  { etEmail.setError(getString(R.string.error_email_required));    return; }
            if (pass.isEmpty())   { etPassword.setError(getString(R.string.error_password_required)); return; }
            viewModel.login(email, pass);
        });

        TextView tvRegister = findViewById(R.id.tvGoToRegister);
        if (tvRegister != null)
            tvRegister.setOnClickListener(v ->
                startActivity(new Intent(this, RegisterActivity.class)));

        viewModel.getState().observe(this, state -> {
            switch (state) {
                case LOADING:
                    btnLogin.setEnabled(false);
                    if (progress != null) progress.setVisibility(View.VISIBLE);
                    break;
                case SUCCESS:
                    startActivity(new Intent(this, MainActivity.class)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
                    finish();
                    break;
                case ERROR:
                    btnLogin.setEnabled(true);
                    if (progress != null) progress.setVisibility(View.GONE);
                    break;
                default:
                    btnLogin.setEnabled(true);
                    if (progress != null) progress.setVisibility(View.GONE);
            }
        });

        viewModel.getMessage().observe(this, msg -> {
            if (msg != null) Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
        });
    }
}
