import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    var filtered: [VPNServer] {
        if query.isEmpty { return appState.servers }
        return appState.servers.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.country.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List(filtered) { server in
                Button(action: {
                    appState.selectedServer = server
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name).font(.headline).foregroundColor(.white)
                            Text("\(server.country) · \(server.city)")
                                .font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        Text("\(server.latencyMs)ms")
                            .font(.caption).foregroundColor(Color(hex: "00F0FF"))
                        loadBadge(server.currentLoad)
                    }
                }
                .listRowBackground(Color(hex: "0D1220"))
            }
            .searchable(text: $query, prompt: "Search servers")
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(hex: "070A12"))
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color(hex: "00F0FF"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func loadBadge(_ load: Int) -> some View {
        let (label, color): (String, Color) = load < 30
            ? ("Low", Color(hex: "00E676"))
            : load < 70 ? ("Med", Color(hex: "FFD740")) : ("High", Color(hex: "FF5252"))
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(10)
    }
}