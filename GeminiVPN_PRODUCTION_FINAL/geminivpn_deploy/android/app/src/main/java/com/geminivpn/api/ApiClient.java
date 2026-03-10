package com.geminivpn.api;

import android.content.Context;
import android.util.Log;

import com.geminivpn.BuildConfig;
import com.geminivpn.utils.PreferencesManager;

import java.io.IOException;
import java.util.concurrent.TimeUnit;

import okhttp3.Authenticator;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.Route;
import okhttp3.logging.HttpLoggingInterceptor;
import retrofit2.Retrofit;
import retrofit2.converter.gson.GsonConverterFactory;

/**
 * ApiClient – Retrofit singleton with:
 *   • Bearer-token injection on every request
 *   • Automatic access-token refresh on 401
 *   • Certificate pinning ready (add pins in production)
 */
public class ApiClient {

    private static final String TAG        = "ApiClient";
    private static final int    TIMEOUT_S  = 30;

    private static ApiClient     instance;
    private final  GeminiVpnApi  api;
    private final  PreferencesManager prefs;

    private ApiClient(Context context) {
        prefs = new PreferencesManager(context.getApplicationContext());

        // Logging (debug builds only)
        HttpLoggingInterceptor logging = new HttpLoggingInterceptor(
                message -> Log.d(TAG, message)
        );
        logging.setLevel(BuildConfig.DEBUG
                ? HttpLoggingInterceptor.Level.BODY
                : HttpLoggingInterceptor.Level.NONE);

        OkHttpClient httpClient = new OkHttpClient.Builder()
                .connectTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                .readTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                .writeTimeout(TIMEOUT_S, TimeUnit.SECONDS)
                // Inject Authorization header
                .addInterceptor(chain -> {
                    String token = prefs.getAccessToken();
                    Request original = chain.request();
                    Request.Builder builder = original.newBuilder();
                    if (token != null && !token.isEmpty()) {
                        builder.header("Authorization", "Bearer " + token);
                    }
                    builder.header("Accept", "application/json");
                    return chain.proceed(builder.build());
                })
                // Auto-refresh on 401
                .authenticator(new TokenAuthenticator(prefs))
                .addInterceptor(logging)
                .build();

        Retrofit retrofit = new Retrofit.Builder()
                .baseUrl(BuildConfig.API_BASE_URL + "/")
                .client(httpClient)
                .addConverterFactory(GsonConverterFactory.create())
                .build();

        api = retrofit.create(GeminiVpnApi.class);
    }

    public static synchronized ApiClient getInstance(Context context) {
        if (instance == null) {
            instance = new ApiClient(context);
        }
        return instance;
    }

    public GeminiVpnApi getApi() {
        return api;
    }

    // ─── Token Refresher ──────────────────────────────────────────────────────

    private static class TokenAuthenticator implements Authenticator {

        private final PreferencesManager prefs;

        TokenAuthenticator(PreferencesManager prefs) {
            this.prefs = prefs;
        }

        @Override
        public Request authenticate(Route route, Response response) throws IOException {
            // Avoid infinite retry loop
            if (responseCount(response) >= 2) {
                prefs.clearSession();
                return null;
            }

            String refreshToken = prefs.getRefreshToken();
            if (refreshToken == null) return null;

            // Synchronous refresh call (must NOT use the same client to avoid recursion)
            try {
                // Build a clean client for the token refresh
                OkHttpClient plainClient = new OkHttpClient.Builder()
                        .connectTimeout(10, TimeUnit.SECONDS)
                        .build();

                Retrofit plain = new Retrofit.Builder()
                        .baseUrl(BuildConfig.API_BASE_URL + "/")
                        .client(plainClient)
                        .addConverterFactory(GsonConverterFactory.create())
                        .build();

                GeminiVpnApi refreshApi = plain.create(GeminiVpnApi.class);
                GeminiVpnApi.RefreshTokenRequest req =
                        new GeminiVpnApi.RefreshTokenRequest(refreshToken);

                // Execute synchronously (inside OkHttp authenticator, must be sync)
                retrofit2.Response<ApiResponse<AuthResponse>> refreshResponse =
                        refreshApi.refreshToken(req).execute();

                if (refreshResponse.isSuccessful()
                        && refreshResponse.body() != null
                        && refreshResponse.body().data != null) {

                    AuthResponse auth = refreshResponse.body().data;
                    prefs.saveTokens(auth.tokens.accessToken, auth.tokens.refreshToken);

                    return response.request().newBuilder()
                            .header("Authorization", "Bearer " + auth.tokens.accessToken)
                            .build();
                }
            } catch (Exception e) {
                Log.e(TAG, "Token refresh failed", e);
            }

            prefs.clearSession();
            return null;
        }

        private int responseCount(Response response) {
            int result = 1;
            while ((response = response.priorResponse()) != null) result++;
            return result;
        }
    }
}
