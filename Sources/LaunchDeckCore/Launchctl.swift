import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

// ponytail: immutable runner wrapper; use an actor if runners start carrying mutable state.
public struct CommandRunner: @unchecked Sendable {
    private let runCommand: (_ executable: String, _ arguments: [String]) throws -> CommandResult

    public init(run: @escaping (_ executable: String, _ arguments: [String]) throws -> CommandResult) {
        self.runCommand = run
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        try runCommand(executable, arguments)
    }

    public func runTool(_ tool: String, arguments: [String]) throws -> CommandResult {
        try run("/usr/bin/env", [tool] + arguments)
    }

    public static let live = CommandRunner { executable, arguments in
        let directory = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        let stdoutURL = directory.appending(path: "launchdeck-\(token).stdout")
        let stderrURL = directory.appending(path: "launchdeck-\(token).stderr")

        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        try stdout.close()
        try stderr.close()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? "",
            standardError: String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        )
    }
}

public struct PlistLinter {
    public let runner: CommandRunner

    public init(runner: CommandRunner = .live) {
        self.runner = runner
    }

    public func lint(_ url: URL) throws -> CommandResult {
        try runner.runTool("plutil", arguments: ["-lint", url.path])
    }
}

public struct LaunchctlStatusSnapshot: Equatable, Sendable {
    public let label: String
    public let serviceTarget: String
    public let printResult: CommandResult
    public let disabledResult: CommandResult
}

public struct Launchctl {
    public let uid: Int
    public let runner: CommandRunner

    public init(uid: Int = Int(getuid()), runner: CommandRunner = .live) {
        self.uid = uid
        self.runner = runner
    }

    public var guiDomain: String {
        "gui/\(uid)"
    }

    public func bootstrap(plistURL: URL) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["bootstrap", guiDomain, plistURL.path])
    }

    public func bootout(plistURL: URL) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["bootout", guiDomain, plistURL.path])
    }

    public func enable(label: String) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["enable", serviceTarget(for: label)])
    }

    public func disable(label: String) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["disable", serviceTarget(for: label)])
    }

    public func kickstart(label: String, kill: Bool = true, printPID: Bool = true) throws -> CommandResult {
        var arguments = ["kickstart"]
        let flags = "\(kill ? "k" : "")\(printPID ? "p" : "")"

        if !flags.isEmpty {
            arguments.append("-\(flags)")
        }

        arguments.append(try serviceTarget(for: label))
        return try runner.runTool("launchctl", arguments: arguments)
    }

    public func print(label: String) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["print", serviceTarget(for: label)])
    }

    public func printDisabled() throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["print-disabled", guiDomain])
    }

    public func status(label: String) throws -> LaunchctlStatusSnapshot {
        LaunchctlStatusSnapshot(
            label: label,
            serviceTarget: try serviceTarget(for: label),
            printResult: try print(label: label),
            disabledResult: try printDisabled()
        )
    }

    public func serviceTarget(for label: String) throws -> String {
        try LaunchLabel.validateServiceLabel(label)
        return "\(guiDomain)/\(label)"
    }
}
