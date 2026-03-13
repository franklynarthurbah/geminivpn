// AppState.swift
// GeminiVPN – iOS
// Centralised observable application state.

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - Published

    @Published var isLoggedIn:      Bool        = false
    @Published var currentUser:     UserProfile? = nil
    @Published var servers:         [VPNServer]  = []
    @Published var clients:         [VPNClient]  = []
    @Published var selectedServer:  VPNServer?   = nil
    @Published var activeClient:    VPNClient?   = nil
    @Published var isLoading:       Bool         = false
    @Published var errorMessage:    String?      = nil
    @Published var successMessage:  String?      = nil

    // MARK: - Init

    private init() {
        // Restore login state from Keychain
        isLoggedIn = KeychainManager.shared.get("access_token") != nil
        if isLoggedIn { Task { await loadInitialData() } }
    }

    // MARK: - Auth actions

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let auth = try await ApiService.shared.login(email: email, password: password)
            KeychainManager.shared.set(auth.tokens.accessToken,  forKey: "access_token")
            KeychainManager.shared.set(auth.tokens.refreshToken, forKey: "refresh_token")
            isLoggedIn = true
            await loadInitialData()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, password: String, name: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let auth = try await ApiService.shared.register(email: email, password: password, name: name)
            KeychainManager.shared.set(auth.tokens.accessToken,  forKey: "access_token")
            KeychainManager.shared.set(auth.tokens.refreshToken, forKey: "refresh_token")
            isLoggedIn = true
            await loadInitialData()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() async {
        try? await ApiService.shared.logout()
        KeychainManager.shared.deleteAll()
        currentUser    = nil
        servers        = []
        clients        = []
        selectedServer = nil
        activeClient   = nil
        isLoggedIn     = false
    }

    // MARK: - Data loading

    func loadInitialData() async {
        async let profile = ApiService.shared.getProfile()
        async let serverList = ApiService.shared.getServers()
        async let clientList = ApiService.shared.getClients()

        do {
            let (p, s, c) = try await (profile, serverList, clientList)
            currentUser = p
            servers     = s
            clients     = c

            // Auto-select best server (lowest latency)
            selectedServer = s.filter { $0.isActive }
                              .min(by: { $0.latencyMs < $1.latencyMs })

            // Active client = first connected or most recent
            activeClient = c.first(where: { $0.isConnected }) ?? c.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - VPN provisioning

    /// Creates a new VPN client for the selected server if none exists, then connects.
    func autoProvisionAndConnect() async throws {
        guard let server = selectedServer else {
            throw VPNError.configurationInvalid
        }

        let deviceName = UIDevice.current.name + " (iOS)"

        // Create client
        let newClient = try await ApiService.shared.createClient(
            name: deviceName, serverId: server.id
        )
        clients.append(newClient)
        activeClient = newClient

        // Connect
        try await VPNManager.shared.connect(client: newClient, server: server)
    }

    // MARK: - Subscription helpers

    var subscriptionIsActive: Bool {
        let status = currentUser?.subscriptionStatus ?? "trial"
        return status == "active" || status == "trial"
    }

    var subscriptionLabel: String {
        switch currentUser?.subscriptionStatus {
        case "active": return "Active"
        case "trial":  return "Trial"
        case "expired": return "Expired"
        default:        return "Unknown"
        }
    }
}
