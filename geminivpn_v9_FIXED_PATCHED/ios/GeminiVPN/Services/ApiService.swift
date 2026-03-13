// ApiService.swift
// GeminiVPN – iOS
// Handles all REST calls to the GeminiVPN backend API with
// automatic token refresh and secure Keychain storage.

import Foundation

// MARK: - ApiService

@MainActor
final class ApiService {

    static let shared = ApiService()

    // MARK: - Config

    private let baseURL: URL = {
        #if DEBUG
        return URL(string: "http://localhost:5000/v1")!
        #else
        return URL(string: "https://geminivpn.zapto.org/api/v1")!
        #endif
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    private let keychain = KeychainManager.shared
    private let decoder  = JSONDecoder()

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Auth

    func register(email: String, password: String, name: String) async throws -> AuthResponse {
        let body: [String: String] = ["email": email, "password": password, "name": name]
        let resp: ApiWrapper<AuthResponse> = try await post("auth/register", body: body)
        saveTokens(resp.data)
        return resp.data
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body: [String: String] = ["email": email, "password": password]
        let resp: ApiWrapper<AuthResponse> = try await post("auth/login", body: body)
        saveTokens(resp.data)
        return resp.data
    }

    func logout() async throws {
        guard let refresh = keychain.get("refresh_token") else { return }
        let body = ["refreshToken": refresh]
        let _: ApiWrapper<EmptyData> = try await post("auth/logout", body: body)
        keychain.deleteAll()
    }

    func refreshToken() async throws -> AuthResponse {
        guard let refresh = keychain.get("refresh_token") else {
            throw ApiError.unauthorized
        }
        let body = ["refreshToken": refresh]
        let resp: ApiWrapper<AuthResponse> = try await post("auth/refresh", body: body)
        saveTokens(resp.data)
        return resp.data
    }

    func getProfile() async throws -> UserProfile {
        let resp: ApiWrapper<UserProfile> = try await get("auth/profile")
        return resp.data
    }

    // MARK: - VPN Clients

    func getClients() async throws -> [VPNClient] {
        let resp: ApiWrapper<[VPNClient]> = try await get("vpn/clients")
        return resp.data
    }

    func createClient(name: String, serverId: String) async throws -> VPNClient {
        let body: [String: String] = ["clientName": name, "serverId": serverId]
        let resp: ApiWrapper<VPNClient> = try await post("vpn/clients", body: body)
        return resp.data
    }

    func deleteClient(clientId: String) async throws {
        let _: ApiWrapper<EmptyData> = try await delete("vpn/clients/\(clientId)")
    }

    func connectClient(clientId: String) async throws {
        let _: ApiWrapper<VPNClient> = try await post(
            "vpn/clients/\(clientId)/connect", body: [String: String]()
        )
    }

    func disconnectClient(clientId: String) async throws {
        let _: ApiWrapper<VPNClient> = try await post(
            "vpn/clients/\(clientId)/disconnect", body: [String: String]()
        )
    }

    // MARK: - Servers

    func getServers() async throws -> [VPNServer] {
        let resp: ApiWrapper<[VPNServer]> = try await get("servers")
        return resp.data
    }

    // MARK: - Payments

    func createCheckoutSession(plan: String) async throws -> CheckoutSession {
        let body: [String: String] = [
            "planType":   plan,
            "successUrl": "geminivpn://payment/success",
            "cancelUrl":  "geminivpn://payment/cancel"
        ]
        let resp: ApiWrapper<CheckoutSession> = try await post("payments/checkout", body: body)
        return resp.data
    }

    // MARK: - Generic HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let req = try buildRequest(method: "GET", path: path)
        return try await execute(req)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = try buildRequest(method: "POST", path: path)
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(req)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let req = try buildRequest(method: "DELETE", path: path)
        return try await execute(req)
    }

    private func buildRequest(method: String, path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ApiError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token = keychain.get("access_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.noResponse
        }

        switch http.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)

        case 401:
            // Attempt token refresh once
            let refreshed = try await refreshToken()
            var retryReq  = request
            retryReq.setValue("Bearer \(refreshed.tokens.accessToken)",
                              forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await session.data(for: retryReq)
            guard (retryResp as? HTTPURLResponse)?.statusCode != 401 else {
                throw ApiError.unauthorized
            }
            return try decoder.decode(T.self, from: retryData)

        case 403:
            if let msg = try? decoder.decode(ApiWrapper<EmptyData>.self, from: data).message {
                throw ApiError.forbidden(msg)
            }
            throw ApiError.forbidden("Access denied")

        case 429:
            throw ApiError.rateLimited

        default:
            if let msg = try? decoder.decode(ApiWrapper<EmptyData>.self, from: data).message {
                throw ApiError.serverError(http.statusCode, msg)
            }
            throw ApiError.serverError(http.statusCode, "Request failed")
        }
    }

    // MARK: - Token storage

    private func saveTokens(_ auth: AuthResponse) {
        keychain.set(auth.tokens.accessToken,  forKey: "access_token")
        keychain.set(auth.tokens.refreshToken, forKey: "refresh_token")
    }
}

// MARK: - Response models

struct ApiWrapper<T: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let data:    T
}

struct EmptyData: Decodable {}

struct AuthResponse: Decodable {
    struct User: Decodable {
        let id:                 String
        let email:              String
        let name:               String?
        let subscriptionStatus: String
        let trialEndsAt:        String?
        let subscriptionEndsAt: String?
    }
    struct Tokens: Decodable {
        let accessToken:  String
        let refreshToken: String
        let expiresIn:    Int
    }
    let user:   User
    let tokens: Tokens
}

struct UserProfile: Decodable {
    let id:                 String
    let email:              String
    let name:               String?
    let subscriptionStatus: String
    let trialEndsAt:        String?
    let subscriptionEndsAt: String?
    let isTestUser:         Bool?
    let clients:            [VPNClient]?
}

struct VPNClient: Decodable, Identifiable {
    let id:          String
    let clientName:  String
    let publicKey:   String
    let privateKey:  String?
    let assignedIp:  String
    let serverId:    String?
    let isConnected: Bool
    let configFile:  String?
    let qrCode:      String?
    let server:      VPNServer?
}

struct VPNServer: Decodable, Identifiable {
    let id:             String
    let name:           String
    let country:        String
    let city:           String
    let hostname:       String
    let port:           Int
    let publicKey:      String
    let loadPercentage: Int
    let latencyMs:      Int
    let isActive:       Bool

    var loadLabel: String {
        switch loadPercentage {
        case 0..<30:  return "Low"
        case 30..<70: return "Medium"
        default:       return "High"
        }
    }
}

struct CheckoutSession: Decodable {
    let sessionId: String
    let url:       String
}

// MARK: - Error types

enum ApiError: LocalizedError {
    case invalidURL
    case noResponse
    case unauthorized
    case forbidden(String)
    case rateLimited
    case serverError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid URL."
        case .noResponse:           return "No response from server."
        case .unauthorized:         return "Session expired. Please log in again."
        case .forbidden(let msg):   return msg
        case .rateLimited:          return "Too many requests. Please wait."
        case .serverError(_, let m): return m
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        }
    }
}
