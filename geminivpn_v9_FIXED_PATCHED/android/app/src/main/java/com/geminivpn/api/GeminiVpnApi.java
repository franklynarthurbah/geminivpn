package com.geminivpn.api;

import com.geminivpn.models.Models;
import java.util.List;
import retrofit2.Call;
import retrofit2.http.*;

public interface GeminiVpnApi {

    // ─── Auth ──────────────────────────────────────────────────────────────────
    @POST("auth/register")
    Call<Models.ApiResponse<Models.AuthResponse>> register(@Body Models.RegisterRequest request);

    @POST("auth/login")
    Call<Models.ApiResponse<Models.AuthResponse>> login(@Body Models.LoginRequest request);

    @POST("auth/logout")
    Call<Models.ApiResponse<Void>> logout(@Body Models.RefreshTokenRequest request);

    @POST("auth/refresh")
    Call<Models.ApiResponse<Models.AuthResponse>> refreshToken(@Body Models.RefreshTokenRequest request);

    @GET("auth/profile")
    Call<Models.ApiResponse<Models.UserProfile>> getProfile();

    @GET("auth/subscription")
    Call<Models.ApiResponse<Models.SubscriptionStatus>> checkSubscription();

    // ─── VPN Clients ───────────────────────────────────────────────────────────
    @GET("vpn/clients")
    Call<Models.ApiResponse<List<Models.VPNClient>>> getClients();

    @POST("vpn/clients")
    Call<Models.ApiResponse<Models.VPNClient>> createClient(@Body Models.CreateClientRequest request);

    @GET("vpn/clients/{id}")
    Call<Models.ApiResponse<Models.VPNClient>> getClient(@Path("id") String clientId);

    @DELETE("vpn/clients/{id}")
    Call<Models.ApiResponse<Void>> deleteClient(@Path("id") String clientId);

    @POST("vpn/clients/{id}/connect")
    Call<Models.ApiResponse<Models.VPNClient>> connectClient(@Path("id") String clientId);

    @POST("vpn/clients/{id}/disconnect")
    Call<Models.ApiResponse<Models.VPNClient>> disconnectClient(@Path("id") String clientId);

    @GET("vpn/clients/{id}/config")
    Call<Models.ApiResponse<Models.VPNClient>> getClientConfig(@Path("id") String clientId);

    // ─── Servers ───────────────────────────────────────────────────────────────
    @GET("servers")
    Call<Models.ApiResponse<List<Models.VPNServer>>> getServers();

    // ─── Payments ──────────────────────────────────────────────────────────────
    @POST("payments/checkout")
    Call<Models.ApiResponse<Models.CheckoutResponse>> createCheckoutSession(@Body Models.CheckoutRequest request);
}
