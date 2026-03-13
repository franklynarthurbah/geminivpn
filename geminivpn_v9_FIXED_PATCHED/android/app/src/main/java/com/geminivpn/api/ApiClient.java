package com.geminivpn.api;

import android.content.Context;
import android.util.Log;
import com.geminivpn.BuildConfig;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import java.io.IOException;
import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.logging.HttpLoggingInterceptor;
import retrofit2.Retrofit;
import retrofit2.converter.gson.GsonConverterFactory;

public class ApiClient {

    private static final String TAG       = "ApiClient";
    private static final int    TIMEOUT_S = 30;

    private static ApiClient   instance;
    private final  GeminiVpnApi api;

    private ApiClient(Context context) {
        PreferencesManager prefs = new PreferencesManager(context.getApplicationContext());

        HttpLoggingInterceptor logging = new HttpLoggingInterceptor(msg -> Log.d(TAG, msg));
        logging.setLevel(BuildConfig.DEBUG
                ? HttpLoggingInterceptor.Level.BODY
                : HttpLoggingInterceptor.Level.NONE);

        OkHttpClient httpClient = new OkHttpClient.Builder()
                .connectTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                .readTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                .writeTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                .addInterceptor(chain -> {
                    String token = prefs.getAccessToken();
                    Request.Builder builder = chain.request().newBuilder();
                    if (token != null && !token.isEmpty())
                        builder.header("Authorization", "Bearer " + token);
                    builder.header("Accept", "application/json");
                    return chain.proceed(builder.build());
                })
                .authenticator((route, response) -> {
                    if (responseCount(response) >= 2) { prefs.clearSession(); return null; }
                    String rt = prefs.getRefreshToken();
                    if (rt == null) return null;
                    try {
                        OkHttpClient plain = new OkHttpClient.Builder()
                                .connectTimeout(10, TimeUnit.SECONDS).build();
                        Retrofit r = new Retrofit.Builder()
                                .baseUrl(BuildConfig.API_BASE_URL + "/")
                                .client(plain)
                                .addConverterFactory(GsonConverterFactory.create())
                                .build();
                        retrofit2.Response<Models.ApiResponse<Models.AuthResponse>> res =
                                r.create(GeminiVpnApi.class)
                                 .refreshToken(new Models.RefreshTokenRequest(rt))
                                 .execute();
                        if (res.isSuccessful() && res.body() != null && res.body().data != null) {
                            Models.AuthResponse auth = res.body().data;
                            prefs.saveTokens(auth.tokens.accessToken, auth.tokens.refreshToken);
                            return response.request().newBuilder()
                                    .header("Authorization", "Bearer " + auth.tokens.accessToken)
                                    .build();
                        }
                    } catch (Exception e) { Log.e(TAG, "Token refresh failed", e); }
                    prefs.clearSession();
                    return null;
                })
                .addInterceptor(logging)
                .build();

        api = new Retrofit.Builder()
                .baseUrl(BuildConfig.API_BASE_URL + "/")
                .client(httpClient)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(GeminiVpnApi.class);
    }

    private static int responseCount(Response r) {
        int n = 1; while ((r = r.priorResponse()) != null) n++; return n;
    }

    public static synchronized ApiClient getInstance(Context ctx) {
        if (instance == null) instance = new ApiClient(ctx);
        return instance;
    }

    public GeminiVpnApi getApi() { return api; }

    public static void reset() { instance = null; }
}
