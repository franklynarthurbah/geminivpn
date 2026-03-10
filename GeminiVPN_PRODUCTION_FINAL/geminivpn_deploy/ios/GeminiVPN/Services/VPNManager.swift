// VPNManager.swift
// GeminiVPN – iOS
// Manages VPN tunnel lifecycle using NetworkExtension framework.

import Foundation
import NetworkExtension
import Combine

/// Unified manager for all VPN operations on iOS/iPadOS.
/// Uses NEPacketTunnelProvider (WireGuard-based) via a Network Extension target.
@MainActor
final class VPNManager: ObservableObject {

    // MARK: - Shared instance

    static let shared = VPNManager()

    // MARK: - Published state

    @Published private(set) var connectionState: NEVPNStatus = .disconnected
    @Published private(set) var assignedIP: String?
    @Published private(set) var connectedServer: VPNServer?
    @Published private(set) var bytesIn:  Int64 = 0
    @Published private(set) var bytesOut: Int64 = 0
    @Published private(set) var isKillSwitchEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    // MARK: - Private

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statsTimer: Timer?
    private let bundleIdentifier = "com.geminivpn.tunnel"

    // MARK: - Init

    private init() {
        isKillSwitchEnabled = UserDefaults.standard.bool(forKey: "kill_switch_enabled")
        Task { await loadExistingManager() }
    }

    // MARK: - Setup

    /// Load or create the NETunnelProviderManager for our extension.
    private func loadExistingManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == bundleIdentifier
            }) ?? NETunnelProviderManager()
            observeStatus()
        } catch {
            errorMessage = "Failed to load VPN preferences: \(error.localizedDescription)"
        }
    }

    private func observeStatus() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        connectionState = manager?.connection.status ?? .disconnected
        if connectionState == .connected {
            startStatsPolling()
        } else {
            stopStatsPolling()
            if connectionState == .disconnected && isKillSwitchEnabled {
                // Kill switch: notify UI that traffic is blocked
                NotificationCenter.default.post(
                    name: .killSwitchActivated, object: nil
                )
            }
        }
    }

    // MARK: - Connect

    /// Configure and start the WireGuard tunnel.
    func connect(client: VPNClient, server: VPNServer) async throws {
        guard let manager = manager else { throw VPNError.managerNotLoaded }

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = bundleIdentifier
        tunnelProtocol.serverAddress            = server.hostname

        // Pass WireGuard config to the extension via providerConfiguration
        tunnelProtocol.providerConfiguration = [
            "privateKey":  client.privateKey ?? "",
            "publicKey":   server.publicKey,
            "assignedIP":  client.assignedIp,
            "endpoint":    "\(server.hostname):\(server.port)",
            "dns":         "1.1.1.1,1.0.0.1",
            "mtu":         "1420",
            "killSwitch":  "\(isKillSwitchEnabled)"
        ]

        // Include all-traffic route (full tunnel) and kill-switch flag
        if isKillSwitchEnabled {
            // NEOnDemandRuleDisconnect ensures traffic is blocked when VPN is off
            let killSwitchRule           = NEOnDemandRuleDisconnect()
            killSwitchRule.interfaceTypeMatch = .any
            manager.onDemandRules          = [killSwitchRule]
            manager.isOnDemandEnabled      = false  // manual connect, but rules block non-VPN
        }

        manager.localizedDescription = "GeminiVPN – \(server.city), \(server.country)"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        observeStatus()

        try manager.connection.startVPNTunnel(options: nil)
        connectedServer = server

        // Tell backend we're connected
        try await ApiService.shared.connectClient(clientId: client.id)
    }

    // MARK: - Disconnect

    func disconnect() async throws {
        manager?.connection.stopVPNTunnel()
        stopStatsPolling()
        if let clientId = AppState.shared.activeClient?.id {
            try await ApiService.shared.disconnectClient(clientId: clientId)
        }
        connectedServer = nil
        assignedIP      = nil
    }

    // MARK: - Kill Switch

    func setKillSwitch(enabled: Bool) {
        isKillSwitchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "kill_switch_enabled")
    }

    // MARK: - Stats polling

    private func startStatsPolling() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchTunnelStats()
        }
    }

    private func stopStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func fetchTunnelStats() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        do {
            try session.sendProviderMessage(Data("stats".utf8)) { [weak self] data in
                guard let data = data,
                      let json = try? JSONDecoder().decode(TunnelStats.self, from: data)
                else { return }
                DispatchQueue.main.async {
                    self?.bytesIn  = json.bytesReceived
                    self?.bytesOut = json.bytesSent
                    self?.assignedIP = json.assignedIP
                }
            }
        } catch {
            // Stats not critical – ignore errors
        }
    }

    // MARK: - Computed helpers

    var isConnected: Bool   { connectionState == .connected }
    var isConnecting: Bool  { connectionState == .connecting || connectionState == .reasserting }

    // MARK: - Deinit

    deinit {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - Supporting types

struct TunnelStats: Decodable {
    let bytesReceived: Int64
    let bytesSent:     Int64
    let assignedIP:    String?
}

enum VPNError: LocalizedError {
    case managerNotLoaded
    case configurationInvalid
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .managerNotLoaded:          return "VPN manager could not be loaded."
        case .configurationInvalid:      return "VPN configuration is invalid."
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        }
    }
}

extension Notification.Name {
    static let killSwitchActivated = Notification.Name("GeminiVPNKillSwitchActivated")
}
