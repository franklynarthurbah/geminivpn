package com.geminivpn.ui;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Button;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class SubscriptionActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // TODO: Inflate subscription layout - uses API createCheckoutSession
        // For now, directly open web portal
        Button btnMonthly = new Button(this);
        btnMonthly.setText(getString(R.string.label_plan_monthly));
        btnMonthly.setOnClickListener(v -> openCheckout("MONTHLY"));
    }

    private void openCheckout(String plan) {
        ApiClient.getInstance(this).getApi()
            .createCheckoutSession(new Models.CheckoutRequest(plan, "geminivpn://payment/success", "geminivpn://payment/cancel"))
            .enqueue(new Callback<Models.ApiResponse<Models.CheckoutResponse>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Models.CheckoutResponse>> call,
                        Response<Models.ApiResponse<Models.CheckoutResponse>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        String url = response.body().data.checkoutUrl;
                        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.CheckoutResponse>> call, Throwable t) {
                    Toast.makeText(SubscriptionActivity.this, getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }
}