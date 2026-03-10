package com.geminivpn.ui;

import android.content.Intent;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.textfield.TextInputEditText;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class ServerSelectionActivity extends AppCompatActivity {
    public static final String EXTRA_SERVER_ID   = "server_id";
    public static final String EXTRA_SERVER_NAME = "server_name";
    private List<Models.VPNServer> allServers = new ArrayList<>();
    private RecyclerView recyclerView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_server_selection);
        recyclerView = findViewById(R.id.recyclerServers);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        TextInputEditText etSearch = findViewById(R.id.etSearch);
        etSearch.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int st, int co, int af) {}
            @Override public void onTextChanged(CharSequence s, int st, int be, int co) { filterServers(s.toString()); }
            @Override public void afterTextChanged(Editable s) {}
        });
        findViewById(R.id.btnBack).setOnClickListener(v -> finish());
        loadServers();
    }

    private void loadServers() {
        ApiClient.getInstance(this).getApi().getServers()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNServer>>>() {
                @Override public void onResponse(Call<Models.ApiResponse<List<Models.VPNServer>>> call,
                        Response<Models.ApiResponse<List<Models.VPNServer>>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        allServers = response.body().data;
                        showServers(allServers);
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNServer>>> call, Throwable t) {
                    Toast.makeText(ServerSelectionActivity.this, getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }

    private void filterServers(String query) {
        if (query.isEmpty()) { showServers(allServers); return; }
        List<Models.VPNServer> filtered = allServers.stream()
            .filter(s -> s.name.toLowerCase().contains(query.toLowerCase())
                      || s.country.toLowerCase().contains(query.toLowerCase()))
            .collect(Collectors.toList());
        showServers(filtered);
    }

    private void showServers(List<Models.VPNServer> servers) {
        // Simple inline adapter using ViewHolder pattern
        recyclerView.setAdapter(new RecyclerView.Adapter<RecyclerView.ViewHolder>() {
            @Override public int getItemCount() { return servers.size(); }
            @Override public RecyclerView.ViewHolder onCreateViewHolder(android.view.ViewGroup p, int t) {
                android.view.View v = android.view.LayoutInflater.from(p.getContext())
                    .inflate(R.layout.item_server, p, false);
                return new RecyclerView.ViewHolder(v) {};
            }
            @Override public void onBindViewHolder(RecyclerView.ViewHolder h, int pos) {
                Models.VPNServer s = servers.get(pos);
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvServerName)).setText(s.name);
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvServerLocation)).setText(s.country + " · " + s.city);
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvLatency)).setText(s.latencyMs + "ms");
                String load = s.currentLoad < 30 ? "Low" : s.currentLoad < 70 ? "Med" : "High";
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvLoad)).setText(load);
                h.itemView.setOnClickListener(v -> {
                    Intent result = new Intent();
                    result.putExtra(EXTRA_SERVER_ID, s.id);
                    result.putExtra(EXTRA_SERVER_NAME, s.name);
                    setResult(RESULT_OK, result);
                    finish();
                });
            }
        });
    }
}