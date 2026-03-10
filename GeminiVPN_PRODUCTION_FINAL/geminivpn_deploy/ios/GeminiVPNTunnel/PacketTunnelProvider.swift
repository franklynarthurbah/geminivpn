// PacketTunnelProvider.swift
// GeminiVPN – NetworkExtension Target
// WireGuard-based tunnel implementation.
// This file lives in the separate "GeminiVPNTunnel" extension target.

import NetworkExtension
import os.log

private let log = OSLog(subsystem: "com.geminivpn.tunnel", category: "PacketTunnel")

/// GeminiVPN Packet Tunnel Provider
/// Wraps WireGuard-go (embedded as a C library or via wireguard-apple)
/// to establish a full-traffic WireGuard tunnel.
class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    private var wgHandle: Int32 = -1   // wireguard-go handle

    // ─── Parsed config ────────────────────────────────────────────────────────
    private var privateKey:  String = ""
    private var serverPublicKey: String = ""
    private var assignedIP:  String = ""
    private var endpoint:    String = ""
    private var dns:         [String] = ["1.1.1.1", "1.0.0.1"]
    private var mtu:         Int    = 1420
    private var killSwitch:  Bool   = false

    // MARK: - Tunnel lifecycle

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("Starting GeminiVPN tunnel…", log: log, type: .info)

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let cfg    = proto.providerConfiguration
        else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        // Parse provider configuration
        privateKey       = cfg["privateKey"]   as? String ?? ""
        serverPublicKey  = cfg["publicKey"]    as? String ?? ""
        assignedIP       = cfg["assignedIP"]   as? String ?? ""
        endpoint         = cfg["endpoint"]     as? String ?? ""
        mtu              = Int(cfg["mtu"]      as? String ?? "1420") ?? 1420
        killSwitch       = (cfg["killSwitch"]  as? String) == "true"

        if let dnsStr = cfg["dns"] as? String {
            dns = dnsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        // Validate
        guard !privateKey.isEmpty, !serverPublicKey.isEmpty, !assignedIP.isEmpty else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        // Build network settings
        let settings = buildNetworkSettings()

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                os_log("Failed to apply network settings: %{public}@",
                       log: log, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }

            self?.startWireGuard(completionHandler: completionHandler)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("Stopping tunnel, reason: %d", log: log, type: .info, reason.rawValue)
        stopWireGuard()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let msg = String(data: messageData, encoding: .utf8) ?? ""

        if msg == "stats" {
            let stats = collectStats()
            let data  = try? JSONEncoder().encode(stats)
            completionHandler?(data)
        } else {
            completionHandler?(nil)
        }
    }

    // MARK: - Network settings

    private func buildNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: endpoint)

        // IPv4 full-tunnel
        let ipv4 = NEIPv4Settings(addresses: [assignedIP], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route.default()]     // 0.0.0.0/0 – all traffic through VPN
        if killSwitch {
            ipv4.excludedRoutes = []   // No bypass routes = kill switch
        } else {
            // Exclude VPN server endpoint to prevent routing loop
            if let serverIP = endpoint.components(separatedBy: ":").first {
                ipv4.excludedRoutes = [
                    NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255")
                ]
            }
        }
        settings.ipv4Settings = ipv4

        // IPv6 – block to prevent leaks
        let ipv6 = NEIPv6Settings(addresses: [], networkPrefixLengths: [])
        ipv6.includedRoutes = [NEIPv6Route.default()]   // route ::/0 into tunnel
        settings.ipv6Settings = ipv6

        // DNS
        let dnsSettings = NEDNSSettings(servers: dns)
        dnsSettings.matchDomains = [""]   // intercept ALL DNS queries
        settings.dnsSettings = dnsSettings

        // MTU
        settings.mtu = NSNumber(value: mtu)

        return settings
    }

    // MARK: - WireGuard start / stop

    private func startWireGuard(completionHandler: @escaping (Error?) -> Void) {
        // WireGuard configuration string (wgconf format)
        let wgConfig = buildWireGuardConfig()

        // In a full production build this calls the wireguard-go C bindings:
        //   wgHandle = wgTurnOn(wgConfig, packetFlow.fileDescriptor)
        //
        // For scaffold: log config and signal success so the rest of the
        // app (UI, server sync, kill-switch) can be verified end-to-end.
        os_log("WireGuard config ready (handle will be obtained from wg-go in production)",
               log: log, type: .info)
        os_log("%{private}@", log: log, type: .debug, wgConfig)

        completionHandler(nil)   // success
    }

    private func stopWireGuard() {
        if wgHandle >= 0 {
            // wgTurnOff(wgHandle)
            wgHandle = -1
        }
    }

    private func buildWireGuardConfig() -> String {
        return """
        [Interface]
        PrivateKey = \(privateKey)
        Address = \(assignedIP)/32
        DNS = \(dns.joined(separator: ", "))
        MTU = \(mtu)

        [Peer]
        PublicKey = \(serverPublicKey)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = \(endpoint)
        PersistentKeepalive = 25
        """
    }

    // MARK: - Stats

    private func collectStats() -> TunnelStatsResponse {
        // In production: query wgStats(wgHandle) for rx/tx bytes
        return TunnelStatsResponse(
            bytesReceived: 0,
            bytesSent:     0,
            assignedIP:    assignedIP
        )
    }
}

// MARK: - Supporting types

private struct TunnelStatsResponse: Encodable {
    let bytesReceived: Int64
    let bytesSent:     Int64
    let assignedIP:    String?
}

private enum TunnelError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        "VPN configuration is missing or incomplete."
    }
}
