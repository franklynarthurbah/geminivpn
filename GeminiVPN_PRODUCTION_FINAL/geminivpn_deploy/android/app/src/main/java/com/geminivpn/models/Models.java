package com.geminivpn.models;

import com.google.gson.annotations.SerializedName;
import java.util.List;

// ─── Generic API wrapper ───────────────────────────────────────────────────────

class ApiResponse<T> {
    public boolean success;
    public String message;
    public T data;
    public ApiError error;

    static class ApiError {
        public String code;
        public String message;
    }
}

// ─── Authentication ─────────────────────────────────────────────────────────

class AuthResponse {
    public UserProfile user;
    public Tokens tokens;

    static class Tokens {
        @SerializedName("accessToken")  public String accessToken;
        @SerializedName("refreshToken") public String refreshToken;
        @SerializedName("expiresIn")    public int expiresIn;
    }
}

class LoginRequest {
    public String email;
    public String password;

    public LoginRequest(String email, String password) {
        this.email    = email;
        this.password = password;
    }
}

class RegisterRequest {
    public String email;
    public String password;
    public String name;

    public RegisterRequest(String email, String password, String name) {
        this.email    = email;
        this.password = password;
        this.name     = name;
    }
}

class RefreshTokenRequest {
    @SerializedName("refreshToken")
    public String refreshToken;

    public RefreshTokenRequest(String refreshToken) {
        this.refreshToken = refreshToken;
    }
}

// ─── User Profile ────────────────────────────────────────────────────────────

class UserProfile {
    public String id;
    public String email;
    public String name;
    @SerializedName("subscriptionStatus") public String subscriptionStatus;
    @SerializedName("trialEndsAt")        public String trialEndsAt;
    @SerializedName("subscriptionEndsAt") public String subscriptionEndsAt;
    @SerializedName("isTestUser")         public boolean isTestUser;
    @SerializedName("createdAt")          public String createdAt;
    public List<VPNClient> clients;
}

class SubscriptionStatus {
    @SerializedName("subscriptionStatus") public String subscriptionStatus;
    @SerializedName("trialEndsAt")        public String trialEndsAt;
    @SerializedName("subscriptionEndsAt") public String subscriptionEndsAt;
    @SerializedName("isActive")           public boolean isActive;
}

// ─── VPN Models ──────────────────────────────────────────────────────────────

class VPNClient {
    public String id;
    @SerializedName("userId")      public String userId;
    @SerializedName("clientName")  public String clientName;
    @SerializedName("publicKey")   public String publicKey;
    @SerializedName("assignedIp")  public String assignedIp;
    @SerializedName("serverId")    public String serverId;
    @SerializedName("isConnected") public boolean isConnected;
    @SerializedName("configFile")  public String configFile;
    @SerializedName("qrCode")      public String qrCode;
    @SerializedName("createdAt")   public String createdAt;
    public VPNServer server;

    public String getAssignedIp()  { return assignedIp; }
    public String getConfigFile()  { return configFile; }
    public String getQrCode()      { return qrCode; }
    public boolean isConnected()   { return isConnected; }
}

class VPNServer {
    public String id;
    public String name;
    public String country;
    public String city;
    public String hostname;
    public int port;
    @SerializedName("publicKey")      public String publicKey;
    @SerializedName("loadPercentage") public int loadPercentage;
    @SerializedName("latencyMs")      public int latencyMs;
    @SerializedName("isActive")       public boolean isActive;

    public String getCity()    { return city; }
    public String getCountry() { return country; }

    /** Human-readable load label */
    public String getLoadLabel() {
        if (loadPercentage < 30)  return "Low";
        if (loadPercentage < 70)  return "Medium";
        return "High";
    }
}

class CreateClientRequest {
    @SerializedName("clientName") public String clientName;
    @SerializedName("serverId")   public String serverId;

    public CreateClientRequest(String clientName, String serverId) {
        this.clientName = clientName;
        this.serverId   = serverId;
    }
}
