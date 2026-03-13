package com.geminivpn.ui;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class SubscriptionActivity extends AppCompatActivity {

    private ProgressBar progress;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_subscription);

        progress = findViewById(R.id.progressBar);

        Button btnBack = findViewById(R.id.btnBack);
        if (btnBack != null) btnBack.setOnClickListener(v -> finish());

        setupPlanButton(R.id.btnMonthly,  "MONTHLY");
        setupPlanButton(R.id.btnYearly,   "YEARLY");
        setupPlanButton(R.id.btnTwoYear,  "TWO_YEAR");
    }

    private void setupPlanButton(int btnId, String planType) {
        Button btn = findViewById(btnId);
        if (btn != null) btn.setOnClickListener(v -> openCheckout(planType));
    }

    private void openCheckout(String plan) {
        if (progress != null) progress.setVisibility(View.VISIBLE);
        ApiClient.getInstance(this).getApi()
            .createCheckoutSession(new Models.CheckoutRequest(plan))
            .enqueue(new Callback<Models.ApiResponse<Models.CheckoutResponse>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.CheckoutResponse>> call,
                        Response<Models.ApiResponse<Models.CheckoutResponse>> response) {
                    if (progress != null) progress.setVisibility(View.GONE);
                    if (response.isSuccessful() && response.body() != null
                            && response.body().data != null
                            && response.body().data.url != null) {
                        startActivity(new Intent(Intent.ACTION_VIEW,
                                Uri.parse(response.body().data.url)));
                    } else {
                        Toast.makeText(SubscriptionActivity.this,
                                getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                    }
                }
                @Override public void onFailure(
                        Call<Models.ApiResponse<Models.CheckoutResponse>> call, Throwable t) {
                    if (progress != null) progress.setVisibility(View.GONE);
                    Toast.makeText(SubscriptionActivity.this,
                            getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }
}
