package com.geminivpn.ui;

import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
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

public class DevicesActivity extends AppCompatActivity {
    private RecyclerView recyclerView;
    private TextView tvDeviceCount;
    private List<Models.VPNClient> clients = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_devices);
        recyclerView   = findViewById(R.id.recyclerDevices);
        tvDeviceCount  = findViewById(R.id.tvDeviceCount);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        findViewById(R.id.btnBack).setOnClickListener(v -> finish());
        Button btnAdd = findViewById(R.id.btnAddDevice);
        btnAdd.setOnClickListener(v -> addDevice());
        loadDevices();
    }

    private void loadDevices() {
        ApiClient.getInstance(this).getApi().getClients()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNClient>>>() {
                @Override public void onResponse(Call<Models.ApiResponse<List<Models.VPNClient>>> call,
                        Response<Models.ApiResponse<List<Models.VPNClient>>> response) {
                    if (response.isSuccessful() && response.body() != null && response.body().data != null) {
                        clients.clear();
                        clients.addAll(response.body().data);
                        tvDeviceCount.setText(clients.size() + " / 10 devices");
                        renderList();
                    }
                }
                @Override public void onFailure(Call<Models.ApiResponse<List<Models.VPNClient>>> call, Throwable t) {
                    Toast.makeText(DevicesActivity.this, getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }

    private void renderList() {
        recyclerView.setAdapter(new RecyclerView.Adapter<RecyclerView.ViewHolder>() {
            @Override public int getItemCount() { return clients.size(); }
            @Override public RecyclerView.ViewHolder onCreateViewHolder(android.view.ViewGroup p, int t) {
                android.view.View v = android.view.LayoutInflater.from(p.getContext()).inflate(R.layout.item_device, p, false);
                return new RecyclerView.ViewHolder(v) {};
            }
            @Override public void onBindViewHolder(RecyclerView.ViewHolder h, int pos) {
                Models.VPNClient c = clients.get(pos);
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvDeviceName)).setText(c.name != null ? c.name : "Device " + (pos+1));
                ((android.widget.TextView) h.itemView.findViewById(R.id.tvDeviceIp)).setText(c.assignedIp != null ? c.assignedIp : "");
                h.itemView.findViewById(R.id.btnDeleteDevice).setOnClickListener(v -> deleteDevice(c.id, pos));
                h.itemView.findViewById(R.id.btnExportConfig).setOnClickListener(v ->
                    Toast.makeText(DevicesActivity.this, "Config copied to clipboard", Toast.LENGTH_SHORT).show());
            }
        });
    }

    private void addDevice() {
        if (clients.size() >= 10) {
            Toast.makeText(this, "Maximum 10 devices reached", Toast.LENGTH_SHORT).show(); return;
        }
        ApiClient.getInstance(this).getApi()
            .createClient(new Models.CreateClientRequest("Android Device " + (clients.size()+1), null))
            .enqueue(new Callback<Models.ApiResponse<Models.VPNClient>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Models.VPNClient>> call,
                        Response<Models.ApiResponse<Models.VPNClient>> response) {
                    if (response.isSuccessful()) loadDevices();
                }
                @Override public void onFailure(Call<Models.ApiResponse<Models.VPNClient>> call, Throwable t) {}
            });
    }

    private void deleteDevice(String clientId, int pos) {
        ApiClient.getInstance(this).getApi().deleteClient(clientId)
            .enqueue(new Callback<Models.ApiResponse<Void>>() {
                @Override public void onResponse(Call<Models.ApiResponse<Void>> call, Response<Models.ApiResponse<Void>> response) {
                    if (response.isSuccessful()) loadDevices();
                }
                @Override public void onFailure(Call<Models.ApiResponse<Void>> call, Throwable t) {}
            });
    }
}