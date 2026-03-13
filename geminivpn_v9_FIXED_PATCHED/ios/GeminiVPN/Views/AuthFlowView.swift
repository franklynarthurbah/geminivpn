import SwiftUI

struct AuthFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Logo
                VStack(spacing: 8) {
                    Text("◆ GeminiVPN")
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(Color(hex: "00F0FF"))
                    Text("Secure. Private. Fast.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 60)
                .padding(.bottom, 48)

                // Error banner
                if let err = errorMsg {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                // Fields
                VStack(spacing: 16) {
                    if !isLogin {
                        GeminiTextField(placeholder: "Full Name", text: $name)
                    }
                    GeminiTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                    GeminiTextField(placeholder: "Password", text: $password, isSecure: true)
                }
                .padding(.horizontal, 24)

                // Submit
                Button(action: submit) {
                    Group {
                        if appState.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text(isLogin ? "Sign In" : "Create Account")
                                .font(.headline)
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .background(Color(hex: "00F0FF"))
                .cornerRadius(27)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .disabled(appState.isLoading)

                // Toggle
                Button(isLogin ? "Don't have an account? Register" : "Already have an account? Sign In") {
                    isLogin.toggle(); errorMsg = nil
                }
                .font(.subheadline)
                .foregroundColor(Color(hex: "00F0FF"))
                .padding(.top, 20)
            }
        }
        .background(Color(hex: "070A12").ignoresSafeArea())
    }

    private func submit() {
        errorMsg = nil
        Task {
            do {
                if isLogin {
                    try await ApiService.shared.login(email: email, password: password)
                } else {
                    try await ApiService.shared.register(name: name, email: email, password: password)
                }
                await appState.loadInitialData()
                appState.isLoggedIn = true
            } catch ApiError.unauthorized {
                errorMsg = "Invalid email or password"
            } catch {
                errorMsg = "Network error. Please try again."
            }
        }
    }
}

struct GeminiTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
            }
        }
        .padding(14)
        .background(Color(hex: "0D1220"))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "1A2340"), lineWidth: 1))
        .foregroundColor(.white)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}