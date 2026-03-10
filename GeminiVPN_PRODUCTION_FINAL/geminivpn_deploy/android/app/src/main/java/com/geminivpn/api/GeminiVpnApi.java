package com.geminivpn.api;

import com.geminivpn.models.ApiResponse;
import com.geminivpn.models.AuthResponse;
import com.geminivpn.models.LoginRequest;
import com.geminivpn.models.RegisterRequest;
import com.geminivpn.models.RefreshTokenRequest;
import com.geminivpn.models.VPNClient;
import com.geminivpn.models.VPNServer;
import com.geminivpn.models.CreateClientRequest;
import com.geminivpn.models.UserProfile;
import com.geminivpn.models.SubscriptionStatus;

import java.util.List;

import retrofit2.Call;
import retrofit2.http.Body;
import retrofit2.http.DELETE;
import retrofit2.http.GET;
import retrofit2.http.Header;
import retrofit2.http.POST;
import retrofit2.http.Path;

/**
 * GeminiVPN REST API interface (Retrofit)
 * Maps to the existing Node.js/Express backend endpoints.
 */
public interface GeminiVpnApi {

    // ─── Authentication ────────────────────────────────────────────────────────

    @POST("auth/register")
    Call<ApiResponse<AuthResponse>> register(@Body RegisterRequest request);

    @POST("auth/login")
    Call<ApiResponse<AuthResponse>> login(@Body LoginRequest request);

    @POST("auth/logout")
    Call<ApiResponse<Void>> logout(
            @Header("Authorization") String bearerToken,
            @Body RefreshTokenRequest request
    );

    @POST("auth/refresh")
    Call<ApiResponse<AuthResponse>> refreshToken(@Body RefreshTokenRequest request);

    @GET("auth/profile")
    Call<ApiResponse<UserProfile>> getProfile(@Header("Authorization") String bearerToken);

    @GET("auth/subscription")
    Call<ApiResponse<SubscriptionStatus>> checkSubscription(
            @Header("Authorization") String bearerToken
    );

    // ─── VPN Clients ───────────────────────────────────────────────────────────

    @GET("vpn/clients")
    Call<ApiResponse<List<VPNClient>>> getClients(
            @Header("Authorization") String bearerToken
    );

    @POST("vpn/clients")
    Call<ApiResponse<VPNClient>> createClient(
            @Header("Authorization") String bearerToken,
            @Body CreateClientRequest request
    );

    @GET("vpn/clients/{id}")
    Call<ApiResponse<VPNClient>> getClient(
            @Header("Authorization") String bearerToken,
            @Path("id") String clientId
    );

    @DELETE("vpn/clients/{id}")
    Call<ApiResponse<Void>> deleteClient(
            @Header("Authorization") String bearerToken,
            @Path("id") String clientId
    );

    @POST("vpn/clients/{id}/connect")
    Call<ApiResponse<VPNClient>> connectClient(
            @Header("Authorization") String bearerToken,
            @Path("id") String clientId
    );

    @POST("vpn/clients/{id}/disconnect")
    Call<ApiResponse<VPNClient>> disconnectClient(
            @Header("Authorization") String bearerToken,
            @Path("id") String clientId
    );

    @GET("vpn/clients/{id}/status")
    Call<ApiResponse<VPNClient>> getClientStatus(
            @Header("Authorization") String bearerToken,
            @Path("id") String clientId
    );

    // ─── Servers ───────────────────────────────────────────────────────────────

    @GET("servers")
    Call<ApiResponse<List<VPNServer>>> getServers(
            @Header("Authorization") String bearerToken
    );

    // ─── Payments ──────────────────────────────────────────────────────────────

    @POST("payments/checkout")
    Call<ApiResponse<CheckoutResponse>> createCheckoutSession(
            @Header("Authorization") String bearerToken,
            @Body CheckoutRequest request
    );

    // ─── Inner request/response classes ───────────────────────────────────────

    class CheckoutRequest {
        public String planType;
        public String successUrl;
        public String cancelUrl;

        public CheckoutRequest(String planType) {
            this.planType   = planType;
            this.successUrl = "geminivpn://payment/success";
            this.cancelUrl  = "geminivpn://payment/cancel";
        }
    }

    class CheckoutResponse {
        public String sessionId;
        public String url;
    }
}
