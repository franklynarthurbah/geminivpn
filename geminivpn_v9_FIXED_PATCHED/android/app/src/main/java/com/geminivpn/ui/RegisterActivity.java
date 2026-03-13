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

public class RegisterActivity extends AppCompatActivity {

    private EditText    etEmail, etPassword, etName;
    private Button      btnRegister;
    private ProgressBar progress;
    private AuthViewModel viewModel;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_register);

        etEmail    = findViewById(R.id.etEmail);
        etPassword = findViewById(R.id.etPassword);
        etName     = findViewById(R.id.etName);
        btnRegister= findViewById(R.id.btnRegister);
        progress   = findViewById(R.id.progressBar);

        viewModel = new ViewModelProvider(this).get(AuthViewModel.class);

        btnRegister.setOnClickListener(v -> {
            String email = etEmail.getText().toString().trim();
            String pass  = etPassword.getText().toString().trim();
            String name  = etName != null ? etName.getText().toString().trim() : "";
            if (email.isEmpty()) { etEmail.setError(getString(R.string.error_email_required)); return; }
            if (pass.isEmpty())  { etPassword.setError(getString(R.string.error_password_required)); return; }
            viewModel.register(email, pass, name);
        });

        TextView tvLogin = findViewById(R.id.tvGoToLogin);
        if (tvLogin != null)
            tvLogin.setOnClickListener(v -> { finish(); });

        viewModel.getState().observe(this, state -> {
            switch (state) {
                case LOADING:
                    btnRegister.setEnabled(false);
                    if (progress != null) progress.setVisibility(View.VISIBLE);
                    break;
                case SUCCESS:
                    startActivity(new Intent(this, MainActivity.class)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
                    finish();
                    break;
                case ERROR:
                    btnRegister.setEnabled(true);
                    if (progress != null) progress.setVisibility(View.GONE);
                    break;
                default:
                    btnRegister.setEnabled(true);
                    if (progress != null) progress.setVisibility(View.GONE);
            }
        });

        viewModel.getMessage().observe(this, msg -> {
            if (msg != null) Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
        });
    }
}
