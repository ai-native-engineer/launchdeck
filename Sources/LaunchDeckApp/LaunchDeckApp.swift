import AppKit
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
    @State private var jobs = LaunchInventoryService().inventory()
    @State private var selection: String?
    @State private var message = ""

    private var selectedJob: LaunchJobSummary? {
        jobs.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(jobs, selection: $selection) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: job.isWritable && job.isAppOwned ? "checkmark.circle" : "lock")
                        Text(job.label)
                            .lineLimit(1)
                    }
                    Text(job.domainName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(LaunchDeck.appName)
            .toolbar {
                Button {
                    jobs = LaunchInventoryService().inventory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        } detail: {
            if let job = selectedJob {
                JobDetailView(job: job, message: $message)
            } else {
                ContentUnavailableView("Select a job", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

private struct JobDetailView: View {
    let job: LaunchJobSummary
    @Binding var message: String

    private var canManage: Bool {
        job.isWritable && job.isAppOwned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(job.label)
                    .font(.title2)
                Text(job.plistURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Load") { run("load") { try Launchctl().bootstrap(plistURL: job.plistURL) } }
                Button("Unload") { run("unload") { try Launchctl().bootout(plistURL: job.plistURL) } }
                Button("Enable") { run("enable") { try Launchctl().enable(label: job.label) } }
                Button("Disable") { run("disable") { try Launchctl().disable(label: job.label) } }
                Button("Run Now") { run("run") { try Launchctl().kickstart(label: job.label) } }
            }
            .disabled(!canManage)

            HStack {
                Button("Diagnose") { diagnose() }
                Button("Open Log") { openLog() }
                    .disabled(job.standardOutPath == nil && job.standardErrorPath == nil)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding()
    }

    private func run(_ name: String, action: () throws -> CommandResult) {
        do {
            let result = try action()
            message = "\(name): exit \(result.exitCode)"
        } catch {
            message = "\(name): \(error)"
        }
    }

    private func openLog() {
        guard let path = job.standardOutPath ?? job.standardErrorPath else {
            return
        }

        NSWorkspace.shared.open(URL(filePath: path))
    }

    private func diagnose() {
        do {
            let status = try Launchctl().status(label: job.label, plistURL: job.plistURL)
            message = status.rawDiagnosticOutput.isEmpty ? "No diagnostic output" : status.rawDiagnosticOutput
        } catch {
            message = "diagnose: \(error)"
        }
    }
}
