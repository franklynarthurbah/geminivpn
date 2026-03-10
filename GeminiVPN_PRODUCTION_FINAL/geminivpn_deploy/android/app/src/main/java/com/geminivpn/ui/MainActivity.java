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
import com.geminivpn.models.VPNClient;
import com.geminivpn.models.VPNServer;
import com.geminivpn.services.GeminiVpnService;
import com.geminivpn.utils.PreferencesManager;
import com.geminivpn.viewmodel.MainViewModel;

/**
 * MainActivity – Primary dashboard screen.
 *
 * Responsibilities:
 *   • One-tap connect / disconnect
 *   • Real-time connection state display
 *   • Kill switch toggle
 *   • Navigate to server selection, device list, settings
 */
public class MainActivity extends AppCompatActivity {

    private ActivityMainBinding  binding;
    private MainViewModel        viewModel;
    private PreferencesManager   prefs;

    // Launcher for VPN permission request dialog
    private final ActivityResultLauncher<Intent> vpnPermissionLauncher =
            registerForActivityResult(
                    new ActivityResultContracts.StartActivityForResult(),
                    result -> {
                        if (result.getResultCode() == RESULT_OK) {
                            startVpnService();
                        } else {
                            showToast("VPN permission denied");
                        }
                    });

    // Broadcast receiver for VPN state changes
    private final BroadcastReceiver stateReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String stateName = intent.getStringExtra(GeminiVpnService.EXTRA_STATE);
            if (stateName != null) {
                updateUiForState(GeminiVpnService.State.valueOf(stateName));
            }
        }
    };

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        prefs = new PreferencesManager(this);

        // Redirect to login if not authenticated
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
        registerReceiver(stateReceiver, filter);
    }

    @Override
    protected void onPause() {
        super.onPause();
        unregisterReceiver(stateReceiver);
    }

    // ─── UI Setup ────────────────────────────────────────────────────────────

    private void setupUI() {
        // Connect / Disconnect button
        binding.btnConnect.setOnClickListener(v -> onConnectButtonClicked());

        // Server selector row
        binding.rowServer.setOnClickListener(v ->
                startActivity(new Intent(this, ServerSelectionActivity.class)));

        // Devices row
        binding.rowDevices.setOnClickListener(v ->
                startActivity(new Intent(this, DevicesActivity.class)));

        // Settings
        binding.btnSettings.setOnClickListener(v ->
                startActivity(new Intent(this, SettingsActivity.class)));

        // Kill switch toggle
        binding.switchKillSwitch.setChecked(prefs.isKillSwitchEnabled());
        binding.switchKillSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            prefs.setKillSwitchEnabled(isChecked);
            viewModel.setKillSwitchEnabled(isChecked);
        });

        // Initial UI state
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

    // ─── Connection logic ─────────────────────────────────────────────────────

    private void onConnectButtonClicked() {
        GeminiVpnService.State state = viewModel.getCurrentState();

        if (state == GeminiVpnService.State.CONNECTED) {
            disconnectVpn();
        } else if (state == GeminiVpnService.State.IDLE
                || state == GeminiVpnService.State.ERROR) {
            requestVpnPermissionAndConnect();
        }
    }

    private void requestVpnPermissionAndConnect() {
        Intent permissionIntent = VpnService.prepare(this);
        if (permissionIntent != null) {
            // System needs to show VPN permission dialog
            vpnPermissionLauncher.launch(permissionIntent);
        } else {
            // Permission already granted
            startVpnService();
        }
    }

    private void startVpnService() {
        VPNClient  client = viewModel.getActiveClient().getValue();
        VPNServer  server = viewModel.getSelectedServer().getValue();

        if (client == null || server == null) {
            viewModel.createClientAndConnect(this);
            return;
        }

        prefs.saveCurrentClient(client);
        prefs.saveCurrentServer(server);

        Intent serviceIntent = new Intent(this, GeminiVpnService.class);
        serviceIntent.setAction(GeminiVpnService.ACTION_CONNECT);
        serviceIntent.putExtra(GeminiVpnService.EXTRA_CLIENT_ID, client.id);
        serviceIntent.putExtra(GeminiVpnService.EXTRA_SERVER_ID, server.id);
        startForegroundService(serviceIntent);
    }

    private void disconnectVpn() {
        Intent serviceIntent = new Intent(this, GeminiVpnService.class);
        serviceIntent.setAction(GeminiVpnService.ACTION_DISCONNECT);
        startService(serviceIntent);
    }

    // ─── State-driven UI updates ──────────────────────────────────────────────

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
                binding.btnConnect.setText("Disconnect");
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_green);
                binding.tvStatus.setText("Connected");
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
                binding.btnConnect.setText("Retry");
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_red);
                binding.tvStatus.setText(prefs.isKillSwitchEnabled()
                        ? "Kill Switch Active" : "Disconnected");
                binding.progressBar.setVisibility(View.GONE);
                break;

            default: // IDLE
                binding.btnConnect.setText("Connect");
                binding.btnConnect.setEnabled(true);
                binding.statusDot.setBackgroundResource(R.drawable.dot_grey);
                binding.tvStatus.setText("Not Connected");
                binding.progressBar.setVisibility(View.GONE);
                binding.tvAssignedIp.setText("");
                break;
        }
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }
}
