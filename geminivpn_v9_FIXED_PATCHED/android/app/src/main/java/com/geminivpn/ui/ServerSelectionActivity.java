package com.geminivpn.ui;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import com.geminivpn.utils.PreferencesManager;
import java.util.ArrayList;
import java.util.List;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class ServerSelectionActivity extends AppCompatActivity {

    private final List<Models.VPNServer> serverList = new ArrayList<>();
    private ServerAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_server_selection);

        Button btnBack = findViewById(R.id.btnBack);
        if (btnBack != null) btnBack.setOnClickListener(v -> finish());

        RecyclerView rv = findViewById(R.id.rvServers);
        if (rv != null) {
            rv.setLayoutManager(new LinearLayoutManager(this));
            adapter = new ServerAdapter(serverList, server -> {
                new PreferencesManager(this).saveCurrentServer(server);
                Intent result = new Intent();
                result.putExtra("server_id", server.id);
                setResult(RESULT_OK, result);
                finish();
            });
            rv.setAdapter(adapter);
        }

        loadServers();
    }

    private void loadServers() {
        ApiClient.getInstance(this).getApi().getServers()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNServer>>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<List<Models.VPNServer>>> call,
                        Response<Models.ApiResponse<List<Models.VPNServer>>> response) {
                    if (response.isSuccessful() && response.body() != null
                            && response.body().data != null) {
                        serverList.clear();
                        serverList.addAll(response.body().data);
                        if (adapter != null) adapter.notifyDataSetChanged();
                    }
                }
                @Override public void onFailure(
                        Call<Models.ApiResponse<List<Models.VPNServer>>> call, Throwable t) {
                    Toast.makeText(ServerSelectionActivity.this,
                            "Failed to load servers", Toast.LENGTH_SHORT).show();
                }
            });
    }

    // ── Inline RecyclerView Adapter ─────────────────────────────────────────

    interface OnServerClickListener { void onServerClick(Models.VPNServer server); }

    static class ServerAdapter extends RecyclerView.Adapter<ServerAdapter.VH> {
        private final List<Models.VPNServer>  items;
        private final OnServerClickListener listener;

        ServerAdapter(List<Models.VPNServer> items, OnServerClickListener l) {
            this.items = items; this.listener = l;
        }

        @Override public VH onCreateViewHolder(android.view.ViewGroup p, int t) {
            android.view.View v = android.view.LayoutInflater.from(p.getContext())
                    .inflate(R.layout.item_server, p, false);
            return new VH(v);
        }

        @Override public void onBindViewHolder(VH h, int i) {
            Models.VPNServer s = items.get(i);
            if (h.tvName    != null) h.tvName.setText(s.name);
            if (h.tvLatency != null) h.tvLatency.setText(s.latencyMs + " ms");
            if (h.tvLoad    != null) h.tvLoad.setText(s.getLoadLabel());
            h.itemView.setOnClickListener(v -> listener.onServerClick(s));
        }

        @Override public int getItemCount() { return items.size(); }

        static class VH extends RecyclerView.ViewHolder {
            android.widget.TextView tvName, tvLatency, tvLoad;
            VH(android.view.View v) {
                super(v);
                tvName    = v.findViewById(R.id.tvServerName);
                tvLatency = v.findViewById(R.id.tvLatency);
                tvLoad    = v.findViewById(R.id.tvLoad);
            }
        }
    }
}
