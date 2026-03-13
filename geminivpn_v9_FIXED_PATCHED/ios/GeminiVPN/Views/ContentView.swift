// ContentView.swift
// GeminiVPN – iOS/iPadOS
// Root SwiftUI view with tab navigation.

import SwiftUI
import NetworkExtension

struct ContentView: View {
    @StateObject private var vpnManager  = VPNManager.shared
    @StateObject private var appState    = AppState.shared
    @State private var showKillSwitchAlert = false

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainTabView()
                    .environmentObject(vpnManager)
                    .environmentObject(appState)
            } else {
                AuthFlowView()
                    .environmentObject(appState)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .killSwitchActivated)) { _ in
            showKillSwitchAlert = true
        }
        .alert("Kill Switch Active", isPresented: $showKillSwitchAlert) {
            Button("Reconnect") { Task { try? await vpnManager.connect(
                client: appState.activeClient!, server: appState.selectedServer!) } }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Your internet is blocked to protect your privacy. Reconnect to restore access.")
        }
    }
}

// MARK: - Main tab view

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home",    systemImage: "shield.fill") }

            ServerListView()
                .tabItem { Label("Servers", systemImage: "globe") }

            DevicesView()
                .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .accentColor(.cyan)
    }
}

// MARK: - Home / Dashboard

struct HomeView: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @EnvironmentObject private var appState:   AppState
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 32) {
                    // Status ring
                    ConnectionRingView(state: vpnManager.connectionState)
                        .frame(width: 200, height: 200)
                        .padding(.top, 32)

                    // IP & server info
                    if vpnManager.isConnected {
                        VStack(spacing: 6) {
                            if let ip = vpnManager.assignedIP {
                                Text(ip)
                                    .font(.system(.title3, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            if let server = vpnManager.connectedServer {
                                Text("\(server.city), \(server.country)")
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 16) {
                                StatBadge(label: "↓", value: formatBytes(vpnManager.bytesIn))
                                StatBadge(label: "↑", value: formatBytes(vpnManager.bytesOut))
                            }
                            .font(.caption)
                        }
                    }

                    // Server selector
                    ServerSelectorRow()
                        .padding(.horizontal)

                    // Connect button
                    ConnectButton(isConnecting: $isConnecting)
                        .padding(.horizontal, 40)

                    // Kill switch toggle
                    Toggle("Kill Switch", isOn: Binding(
                        get:  { vpnManager.isKillSwitchEnabled },
                        set:  { vpnManager.setKillSwitch(enabled: $0) }
                    ))
                    .tint(.cyan)
                    .padding(.horizontal, 32)

                    Spacer()
                }
            }
            .navigationTitle("GeminiVPN")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", Double(bytes) / 1024) : String(format: "%.1f MB", mb)
    }
}

// MARK: - Connection ring animation

struct ConnectionRingView: View {
    let state: NEVPNStatus
    @State private var pulse = false

    var statusColor: Color {
        switch state {
        case .connected:               return .green
        case .connecting, .reasserting: return .yellow
        case .disconnecting:           return .orange
        default:                       return .gray
        }
    }

    var statusText: String {
        switch state {
        case .connected:               return "Protected"
        case .connecting, .reasserting: return "Connecting"
        case .disconnecting:           return "Disconnecting"
        default:                       return "Unprotected"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(statusColor.opacity(0.2), lineWidth: 20)

            Circle()
                .stroke(statusColor, lineWidth: 4)
                .scaleEffect(pulse ? 1.1 : 1.0)
                .opacity(pulse ? 0.4 : 1.0)

            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80)
                .foregroundColor(statusColor)

            Text(statusText)
                .font(.caption.bold())
                .foregroundColor(statusColor)
                .offset(y: 56)
        }
        .onAppear {
            if state == .connecting || state == .reasserting {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - Connect Button

struct ConnectButton: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @EnvironmentObject private var appState:   AppState
    @Binding var isConnecting: Bool

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack {
                if isConnecting {
                    ProgressView().tint(.white)
                }
                Text(buttonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .disabled(vpnManager.connectionState == .connecting
               || vpnManager.connectionState == .disconnecting)
    }

    private var buttonTitle: String {
        switch vpnManager.connectionState {
        case .connected:               return "Disconnect"
        case .connecting, .reasserting: return "Connecting…"
        case .disconnecting:           return "Disconnecting…"
        default:                       return "Connect"
        }
    }

    private var buttonColor: Color {
        vpnManager.isConnected ? .red.opacity(0.85) : .cyan
    }

    private func handleTap() {
        Task {
            isConnecting = true
            do {
                if vpnManager.isConnected {
                    try await vpnManager.disconnect()
                } else {
                    guard let client = appState.activeClient,
                          let server = appState.selectedServer else {
                        // Auto-create client then connect
                        try await appState.autoProvisionAndConnect()
                        return
                    }
                    try await vpnManager.connect(client: client, server: server)
                }
            } catch {
                appState.errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

// MARK: - Server selector row

struct ServerSelectorRow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationLink(destination: ServerListView()) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.selectedServer?.name ?? "Select Server")
                        .font(.headline)
                    if let server = appState.selectedServer {
                        Text("\(server.city) • \(server.loadLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat badge

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundColor(.secondary)
            Text(value).foregroundColor(.primary)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
