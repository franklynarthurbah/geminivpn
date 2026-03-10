import SwiftUI

struct AccountView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            List {
                // Profile section
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "00F0FF"), Color(hex: "7C4DFF")],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                            .overlay(Text(appState.currentUser?.name.prefix(1).uppercased() ?? "?")
                                .font(.title2.bold()).foregroundColor(.black))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.currentUser?.name ?? "—").font(.headline).foregroundColor(.white)
                            Text(appState.currentUser?.email ?? "—").font(.caption).foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 6)
                } header: { Text("Account").foregroundColor(.gray) }
                .listRowBackground(Color(hex: "0D1220"))

                // Subscription section
                Section {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(appState.currentUser?.subscriptionStatus.capitalized ?? "Free")
                            .foregroundColor(Color(hex: "00E676"))
                    }
                    HStack {
                        Text("Devices")
                        Spacer()
                        Text("\(appState.clients.count) / 10").foregroundColor(.gray)
                    }
                } header: { Text("Subscription").foregroundColor(.gray) }
                .listRowBackground(Color(hex: "0D1220"))
                .foregroundColor(.white)

                // Sign out
                Section {
                    Button("Sign Out", role: .destructive) { showLogoutConfirm = true }
                } .listRowBackground(Color(hex: "0D1220"))
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "070A12").ignoresSafeArea())
            .navigationTitle("Account")
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Sign out of GeminiVPN?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task {
                    try? await ApiService.shared.logout()
                    KeychainManager.shared.deleteAll()
                    appState.isLoggedIn = false
                }
            }
        }
    }
}