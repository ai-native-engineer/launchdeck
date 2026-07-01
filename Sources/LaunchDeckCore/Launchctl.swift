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
    public let plistURL: URL?
    public let plistExists: Bool
    public let loaded: Bool
    public let runningPID: Int?
    public let lastExitStatus: Int?
    public let disabled: Bool?
    public let listResult: CommandResult
    public let printResult: CommandResult
    public let disabledResult: CommandResult

    public var rawDiagnosticOutput: String {
        [
            listResult.standardOutput,
            listResult.standardError,
            printResult.standardOutput,
            printResult.standardError,
            disabledResult.standardOutput,
            disabledResult.standardError,
        ].joined(separator: "\n")
    }
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

    public func list(label: String) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["list", label])
    }

    public func print(label: String) throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["print", serviceTarget(for: label)])
    }

    public func printDisabled() throws -> CommandResult {
        try runner.runTool("launchctl", arguments: ["print-disabled", guiDomain])
    }

    public func status(label: String, plistURL: URL? = nil, fileManager: FileManager = .default) throws -> LaunchctlStatusSnapshot {
        let listResult = try list(label: label)
        let printResult = try print(label: label)
        let disabledResult = try printDisabled()
        let parsedList = Self.parseListOutput(listResult.standardOutput)

        return LaunchctlStatusSnapshot(
            label: label,
            serviceTarget: try serviceTarget(for: label),
            plistURL: plistURL,
            plistExists: plistURL.map { fileManager.fileExists(atPath: $0.path) } ?? false,
            loaded: listResult.succeeded,
            runningPID: parsedList.pid,
            lastExitStatus: parsedList.lastExitStatus,
            disabled: disabledResult.succeeded ? Self.parseDisabled(label: label, output: disabledResult.standardOutput) : nil,
            listResult: listResult,
            printResult: printResult,
            disabledResult: disabledResult
        )
    }

    public func serviceTarget(for label: String) throws -> String {
        try LaunchLabel.validateServiceLabel(label)
        return "\(guiDomain)/\(label)"
    }

    private static func parseListOutput(_ output: String) -> (pid: Int?, lastExitStatus: Int?) {
        let pid = intField("PID", in: output)
        let lastExitStatus = intField("LastExitStatus", in: output)

        if pid != nil || lastExitStatus != nil {
            return (pid, lastExitStatus)
        }

        let rows = output
            .split(separator: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty && $0.first != "PID" }

        guard let row = rows.first, row.count >= 2 else {
            return (nil, nil)
        }

        return (Int(row[0]), Int(row[1]))
    }

    private static func intField(_ name: String, in output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let quotedPrefix = "\"\(name)\" = "
            let plainPrefix = "\(name) = "

            if trimmed.hasPrefix(quotedPrefix) {
                return Int(trimmed.dropFirst(quotedPrefix.count).trimmingCharacters(in: CharacterSet(charactersIn: ";")))
            }

            if trimmed.hasPrefix(plainPrefix) {
                return Int(trimmed.dropFirst(plainPrefix.count).trimmingCharacters(in: CharacterSet(charactersIn: ";")))
            }
        }

        return nil
    }

    private static func parseDisabled(label: String, output: String) -> Bool {
        output.contains("\"\(label)\" => true") || output.contains("\(label) => true")
    }
}
