import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            VStack {
                if appState.clients.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 48)).foregroundColor(.gray)
                        Text("No devices yet").foregroundColor(.gray)
                        Button("Add This Device") { addDevice() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "00F0FF"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(appState.clients) { client in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(client.name ?? "Device").font(.headline).foregroundColor(.white)
                                    Text(client.assignedIp ?? "").font(.caption)
                                        .fontDesign(.monospaced).foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "circle.fill")
                                    .foregroundColor(client.isConnected ? Color(hex: "00E676") : Color.gray)
                                    .font(.caption)
                            }
                            .listRowBackground(Color(hex: "0D1220"))
                            .swipeActions {
                                Button(role: .destructive) { deleteClient(client) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Devices (\(appState.clients.count)/10)")
            .background(Color(hex: "070A12").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addDevice) {
                        Image(systemName: "plus").foregroundColor(Color(hex: "00F0FF"))
                    }.disabled(appState.clients.count >= 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await appState.loadInitialData() }
    }

    private func addDevice() {
        Task {
            do {
                _ = try await ApiService.shared.createClient(name: "iOS Device")
                await appState.loadInitialData()
            } catch {}
        }
    }

    private func deleteClient(_ client: VPNClient) {
        Task {
            do {
                try await ApiService.shared.deleteClient(clientId: client.id)
                await appState.loadInitialData()
            } catch {}
        }
    }
}