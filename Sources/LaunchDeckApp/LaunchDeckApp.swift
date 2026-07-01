import LaunchDeckCore
import SwiftUI

@main
struct LaunchDeckApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchDeckContentView()
        }
    }
}

private struct LaunchDeckContentView: View {
    private let domains = LaunchDomain.standard()

    var body: some View {
        NavigationSplitView {
            List(domains, id: \.name) { domain in
                Label(domain.name, systemImage: domain.allowsWrites ? "checkmark.circle" : "lock")
                    .help(domain.url.path)
            }
            .navigationTitle(LaunchDeck.appName)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inventory")
                    .font(.title2)
                Text("User LaunchAgents are writable. Local and system domains are read-only.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
