package com.geminivpn.ui;

import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.geminivpn.R;
import com.geminivpn.api.ApiClient;
import com.geminivpn.models.Models;
import java.util.ArrayList;
import java.util.List;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

public class DevicesActivity extends AppCompatActivity {

    private final List<Models.VPNClient> deviceList = new ArrayList<>();
    private DeviceAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_devices);

        Button btnBack = findViewById(R.id.btnBack);
        if (btnBack != null) btnBack.setOnClickListener(v -> finish());

        Button btnAdd = findViewById(R.id.btnAddDevice);
        if (btnAdd != null) btnAdd.setOnClickListener(v -> addDevice());

        RecyclerView rv = findViewById(R.id.rvDevices);
        if (rv != null) {
            rv.setLayoutManager(new LinearLayoutManager(this));
            adapter = new DeviceAdapter(deviceList, new DeviceAdapter.OnDeleteClickListener() {
                @Override public void onDelete(String clientId) { deleteDevice(clientId); }
                @Override public void onExport(Models.VPNClient client) { exportConfig(client); }
            });
            rv.setAdapter(adapter);
        }

        loadDevices();
    }

    private void loadDevices() {
        ApiClient.getInstance(this).getApi().getClients()
            .enqueue(new Callback<Models.ApiResponse<List<Models.VPNClient>>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<List<Models.VPNClient>>> call,
                        Response<Models.ApiResponse<List<Models.VPNClient>>> response) {
                    if (response.isSuccessful() && response.body() != null
                            && response.body().data != null) {
                        deviceList.clear();
                        deviceList.addAll(response.body().data);
                        if (adapter != null) adapter.notifyDataSetChanged();
                    }
                }
                @Override public void onFailure(
                        Call<Models.ApiResponse<List<Models.VPNClient>>> call, Throwable t) {
                    Toast.makeText(DevicesActivity.this,
                            "Failed to load devices", Toast.LENGTH_SHORT).show();
                }
            });
    }

    private void addDevice() {
        ApiClient.getInstance(this).getApi()
            .createClient(new Models.CreateClientRequest("Android " + android.os.Build.MODEL, null))
            .enqueue(new Callback<Models.ApiResponse<Models.VPNClient>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Models.VPNClient>> call,
                        Response<Models.ApiResponse<Models.VPNClient>> response) {
                    if (response.isSuccessful()) {
                        loadDevices();
                        Toast.makeText(DevicesActivity.this, "Device added!", Toast.LENGTH_SHORT).show();
                    } else {
                        Toast.makeText(DevicesActivity.this, "Failed to add device", Toast.LENGTH_SHORT).show();
                    }
                }
                @Override public void onFailure(
                        Call<Models.ApiResponse<Models.VPNClient>> call, Throwable t) {
                    Toast.makeText(DevicesActivity.this,
                            getString(R.string.error_network), Toast.LENGTH_SHORT).show();
                }
            });
    }

    private void deleteDevice(String clientId) {
        ApiClient.getInstance(this).getApi().deleteClient(clientId)
            .enqueue(new Callback<Models.ApiResponse<Void>>() {
                @Override public void onResponse(
                        Call<Models.ApiResponse<Void>> call,
                        Response<Models.ApiResponse<Void>> response) {
                    loadDevices();
                }
                @Override public void onFailure(Call<Models.ApiResponse<Void>> call, Throwable t) {}
            });
    }

    interface OnDeleteClickListener { void onDelete(String clientId); void onExport(Models.VPNClient client); }

    static class DeviceAdapter extends RecyclerView.Adapter<DeviceAdapter.VH> {
        private final List<Models.VPNClient>  items;
        private final OnDeleteClickListener listener;

        DeviceAdapter(List<Models.VPNClient> items, OnDeleteClickListener l) {
            this.items = items; this.listener = l;
        }

        @Override public VH onCreateViewHolder(android.view.ViewGroup p, int t) {
            android.view.View v = android.view.LayoutInflater.from(p.getContext())
                    .inflate(R.layout.item_device, p, false);
            return new VH(v);
        }

        @Override public void onBindViewHolder(VH h, int i) {
            Models.VPNClient c = items.get(i);
            if (h.tvName != null) h.tvName.setText(c.name != null ? c.name : "Device " + (i+1));
            if (h.tvIp   != null) h.tvIp.setText(c.assignedIp != null ? c.assignedIp : "");
            if (h.btnDelete != null) h.btnDelete.setOnClickListener(v -> listener.onDelete(c.id));
            if (h.btnExport != null) {
                boolean hasConfig = c.configFile != null && !c.configFile.isEmpty();
                h.btnExport.setEnabled(hasConfig);
                h.btnExport.setOnClickListener(v -> {
                    if (hasConfig) listener.onExport(c);
                });
            }
        }

        @Override public int getItemCount() { return items.size(); }

        static class VH extends RecyclerView.ViewHolder {
            android.widget.TextView tvName, tvIp;
            android.widget.Button   btnDelete;
            android.widget.Button   btnExport;
            VH(android.view.View v) {
                super(v);
                tvName      = v.findViewById(R.id.tvDeviceName);
                tvIp        = v.findViewById(R.id.tvDeviceIp);
                btnDelete   = v.findViewById(R.id.btnDelete);
                btnExport   = v.findViewById(R.id.btnExportConfig);
            }
        }
    }
    private void exportConfig(Models.VPNClient client) {
        if (client.configFile == null || client.configFile.isEmpty()) {
            Toast.makeText(this, "No config available for this device", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            String filename = "GeminiVPN-" + (client.name != null ? client.name.replace(" ", "_") : "device") + ".conf";
            java.io.File dir  = getExternalFilesDir(null);
            java.io.File file = new java.io.File(dir, filename);
            java.io.FileWriter fw = new java.io.FileWriter(file);
            fw.write(client.configFile);
            fw.close();
            android.content.Intent share = new android.content.Intent(android.content.Intent.ACTION_SEND);
            share.setType("text/plain");
            share.putExtra(android.content.Intent.EXTRA_STREAM,
                    androidx.core.content.FileProvider.getUriForFile(
                            this, getPackageName() + ".provider", file));
            share.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(android.content.Intent.createChooser(share, "Export WireGuard Config"));
        } catch (Exception e) {
            Toast.makeText(this, "Export failed: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

}
