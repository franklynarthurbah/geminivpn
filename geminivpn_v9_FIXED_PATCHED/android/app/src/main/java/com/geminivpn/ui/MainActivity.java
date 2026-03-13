package com.geminivpn.ui;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.VpnService;
import android.os.Bundle;
import android.view.View;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.lifecycle.ViewModelProvider;

import com.geminivpn.R;
import com.geminivpn.databinding.ActivityMainBinding;
import com.geminivpn.models.Models;                   // FIX: was VPNClient/VPNServer directly
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;
import com.geminivpn.viewmodel.MainViewModel;

public class MainActivity extends AppCompatActivity {

    private ActivityMainBinding binding;
    private MainViewModel       viewModel;
    private PreferencesManager  prefs;

    private final ActivityResultLauncher<Intent> vpnPermissionLauncher =
            registerForActivityResult(
                    new ActivityResultContracts.StartActivityForResult(),
                    result -> {
                        if (result.getResultCode() == RESULT_OK) startVpnService();
                        else showToast(getString(R.string.error_vpn_permission));
                    });

    private final BroadcastReceiver stateReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String stateName = intent.getStringExtra(GeminiVpnService.EXTRA_STATE);
            if (stateName != null) {
                try { updateUiForState(GeminiVpnService.State.valueOf(stateName)); }
                catch (IllegalArgumentException ignored) {}
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = new PreferencesManager(this);

        if (!prefs.isLoggedIn()) {
            startActivity(new Intent(this, LoginActivity.class));
            finish();
            return;
        }

        binding   = ActivityMainBinding.inflate(getLayoutInflater());
        viewModel = new ViewModelProvider(this).get(MainViewModel.class);
        setContentView(binding.getRoot());
        setupUI();
        observeViewModel();
        viewModel.loadData(this);
    }

    @Override
    protected void onResume() {
        super.onResume();
        IntentFilter filter = new IntentFilter(GeminiVpnService.ACTION_STATE_CHANGED);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(stateReceiver, filter);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        try { unregisterReceiver(stateReceiver); } catch (IllegalArgumentException ignored) {}
    }

    private void setupUI() {
        binding.btnConnect.setOnClickListener(v -> onConnectButtonClicked());
        binding.rowServer.setOnClickListener(v ->
                startActivity(new Intent(this, ServerSelectionActivity.class)));
        binding.rowDevices.setOnClickListener(v ->
                startActivity(new Intent(this, DevicesActivity.class)));
        binding.btnSettings.setOnClickListener(v ->
                startActivity(new Intent(this, SettingsActivity.class)));
        binding.switchKillSwitch.setChecked(prefs.isKillSwitchEnabled());
        binding.switchKillSwitch.setOnCheckedChangeListener((btn, checked) -> {
            prefs.setKillSwitchEnabled(checked);
            viewModel.setKillSwitchEnabled(checked);
        });
        updateUiForState(GeminiVpnService.State.IDLE);
    }

    private void observeViewModel() {
        viewModel.getSelectedServer().observe(this, server -> {
            if (server != null) {
                binding.tvServerName.setText(server.name + " – " + server.city);
                binding.tvServerLoad.setText("Load: " + server.getLoadLabel());
                binding.tvServerLatency.setText(server.latencyMs + " ms");
            } else {
                binding.tvServerName.setText("Select a server");
                binding.tvServerLoad.setText("—");
                binding.tvServerLatency.setText("—");
            }
        });

        viewModel.getActiveClient().observe(this, client -> {
            if (client != null && client.isConnected()) {
                binding.tvAssignedIp.setText("IP: " + client.getAssignedIp());
            } else {
                binding.tvAssignedIp.setText("");
            }
        });

        viewModel.getErrorMessage().observe(this, msg -> {
            if (msg != null && !msg.isEmpty()) showToast(msg);
        });
    }

    private void onConnectButtonClicked() {
        GeminiVpnService.State state = viewModel.getCurrentState();
        if (state == GeminiVpnService.State.CONNECTED) disconnectVpn();
        else if (state == GeminiVpnService.State.IDLE || state == GeminiVpnService.State.ERROR)
            requestVpnPermissionAndConnect();
    }

    private void requestVpnPermissionAndConnect() {
        Intent permIntent = VpnService.prepare(this);
        if (permIntent != null) vpnPermissionLauncher.launch(permIntent);
        else startVpnService();
    }

    private void startVpnService() {
        Models.VPNClient client = viewModel.getActiveClient().getValue();  // FIX: Models.VPNClient
        Models.VPNServer server = viewModel.getSelectedServer().getValue(); // FIX: Models.VPNServer

        if (client == null || server == null) {
            viewModel.createClientAndConnect(this);
            return;
        }

        prefs.saveCurrentClient(client);
        prefs.saveCurrentServer(server);

        Intent svc = new Intent(this, GeminiVpnService.class);
        svc.setAction(GeminiVpnService.ACTION_CONNECT);
        svc.putExtra(GeminiVpnService.EXTRA_CLIENT_ID, client.id);
        svc.putExtra(GeminiVpnService.EXTRA_SERVER_ID, server.id);
        startForegroundService(svc);
    }

    private void disconnectVpn() {
        Intent svc = new Intent(this, GeminiVpnService.class);
        svc.setAction(GeminiVpnService.ACTION_DISCONNECT);
        startService(svc);
    }

    private void updateUiForState(@NonNull GeminiVpnService.State state) {
        viewModel.setCurrentState(state);
        switch (state) {
            case CONNECTING:
                binding.btnConnect.setText("Connecting…");
                binding.btnConnect.setEnabled(false);
                binding.statusDot.setBackgroundResource(R.drawable.dot_yellow);
                binding.tvStatus.setText("Connecting…");
                binding.progressBar.setVisibility(View.VISIBLE);
                break;
            case CONNECTED:
                binding.btnConnect.setText(getString(R.string.btn_disconnect));
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_green);
                binding.tvStatus.setText(getString(R.string.vpn_status_connected));
                binding.progressBar.setVisibility(View.GONE);
                break;
            case DISCONNECTING:
                binding.btnConnect.setText("Disconnecting…");
                binding.btnConnect.setEnabled(false);
                binding.statusDot.setBackgroundResource(R.drawable.dot_yellow);
                binding.tvStatus.setText("Disconnecting…");
                binding.progressBar.setVisibility(View.VISIBLE);
                break;
            case ERROR:
                binding.btnConnect.setText(getString(R.string.btn_retry));
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_red);
                binding.tvStatus.setText(prefs.isKillSwitchEnabled()
                        ? getString(R.string.vpn_status_killswitch) : getString(R.string.vpn_status_error));
                binding.progressBar.setVisibility(View.GONE);
                break;
            default: // IDLE
                binding.btnConnect.setText(getString(R.string.btn_connect));
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_grey);
                binding.tvStatus.setText(getString(R.string.vpn_status_disconnected));
                binding.progressBar.setVisibility(View.GONE);
                binding.tvAssignedIp.setText("");
                break;
        }
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }
}
