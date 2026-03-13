package com.geminivpn.models;

import com.google.gson.annotations.SerializedName;
import java.util.List;

public class Models {

    // ─── Generic API wrapper ────────────────────────────────────────────────

    public static class ApiResponse<T> {
        public boolean success;
        public String  message;
        public T       data;
        public ApiError error;

        public static class ApiError {
            public String code;
            public String message;
        }
    }

    // ─── Authentication ──────────────────────────────────────────────────────

    public static class AuthResponse {
        public UserProfile user;
        public Tokens      tokens;

        public static class Tokens {
            @SerializedName("accessToken")  public String accessToken;
            @SerializedName("refreshToken") public String refreshToken;
            @SerializedName("expiresIn")    public int    expiresIn;
        }
    }

    public static class LoginRequest {
        public String email;
        public String password;
        public LoginRequest(String email, String password) {
            this.email = email; this.password = password;
        }
    }

    public static class RegisterRequest {
        public String email;
        public String password;
        public String name;
        public RegisterRequest(String email, String password, String name) {
            this.email = email; this.password = password; this.name = name;
        }
    }

    public static class RefreshTokenRequest {
        @SerializedName("refreshToken") public String refreshToken;
        public RefreshTokenRequest(String refreshToken) { this.refreshToken = refreshToken; }
    }

    // ─── User Profile ─────────────────────────────────────────────────────────

    public static class UserProfile {
        public String id;
        public String email;
        public String name;
        @SerializedName("subscriptionStatus") public String  subscriptionStatus;
        @SerializedName("trialEndsAt")        public String  trialEndsAt;
        @SerializedName("subscriptionEndsAt") public String  subscriptionEndsAt;
        @SerializedName("isTestUser")         public boolean isTestUser;
        @SerializedName("emailVerified")      public boolean emailVerified;
        @SerializedName("createdAt")          public String  createdAt;
        public List<VPNClient>                               clients;
        public List<Payment>                                 payments;
    }

    public static class SubscriptionStatus {
        @SerializedName("subscriptionStatus") public String  subscriptionStatus;
        @SerializedName("trialEndsAt")        public String  trialEndsAt;
        @SerializedName("subscriptionEndsAt") public String  subscriptionEndsAt;
        @SerializedName("isActive")           public boolean isActive;
    }

    // ─── VPN Models ───────────────────────────────────────────────────────────

    public static class VPNClient {
        public String  id;
        @SerializedName("userId")         public String  userId;
        @SerializedName("name")           public String  name;
        @SerializedName("publicKey")      public String  publicKey;
        @SerializedName("privateKey")     public String  privateKey;
        @SerializedName("assignedIp")     public String  assignedIp;
        @SerializedName("serverId")       public String  serverId;
        @SerializedName("isConnected")    public boolean isConnected;
        @SerializedName("configFile")     public String  configFile;
        @SerializedName("qrCodeData")     public String  qrCodeData;
        @SerializedName("createdAt")      public String  createdAt;
        public VPNServer server;

        public String  getAssignedIp() { return assignedIp; }
        public String  getConfigFile() { return configFile; }
        public String  getQrCode()     { return qrCodeData; }
        public boolean isConnected()   { return isConnected; }
    }

    public static class VPNServer {
        public String id;
        public String name;
        public String country;
        public String city;
        public String region;
        public String hostname;
        public int    port;
        @SerializedName("publicKey")      public String publicKey;
        @SerializedName("loadPercentage") public int    loadPercentage;
        @SerializedName("latencyMs")      public int    latencyMs;
        @SerializedName("maxClients")     public int    maxClients;
        @SerializedName("dnsServers")     public String dnsServers;
        @SerializedName("isActive")       public boolean isActive;
        @SerializedName("isMaintenance")  public boolean isMaintenance;

        public String getCity()    { return city; }
        public String getCountry() { return country; }
        public String getLoadLabel() {
            if (loadPercentage < 30) return "Low";
            if (loadPercentage < 70) return "Medium";
            return "High";
        }
    }

    public static class CreateClientRequest {
        @SerializedName("clientName") public String name;
        @SerializedName("serverId") public String serverId;
        public CreateClientRequest(String name, String serverId) {
            this.name = name; this.serverId = serverId;
        }
    }

    // ─── Payment ──────────────────────────────────────────────────────────────

    public static class Payment {
        public String id;
        @SerializedName("amount")    public int    amount;
        @SerializedName("currency")  public String currency;
        @SerializedName("status")    public String status;
        @SerializedName("provider")  public String provider;
        @SerializedName("planType")  public String planType;
        @SerializedName("createdAt") public String createdAt;
    }

    // ─── Checkout ─────────────────────────────────────────────────────────────

    public static class CheckoutRequest {
        @SerializedName("planType")   public String planType;
        @SerializedName("successUrl") public String successUrl;
        @SerializedName("cancelUrl")  public String cancelUrl;
        public CheckoutRequest(String planType) {
            this.planType   = planType;
            this.successUrl = "geminivpn://payment/success";
            this.cancelUrl  = "geminivpn://payment/cancel";
        }
    }

    public static class CheckoutResponse {
        @SerializedName("sessionId") public String sessionId;
        @SerializedName("url")       public String url;
    }
}
