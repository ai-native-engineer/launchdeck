import Foundation
import LaunchDeckCore

@main
struct LaunchDeckCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("\(error)\n", stderr)
            Darwin.exit(1)
        }
    }

    private static func run(_ args: [String]) throws {
        switch args.first {
        case "domains":
            for domain in LaunchDomain.standard() {
                let mode = domain.allowsWrites ? "writable" : "read-only"
                print("\(domain.name)\t\(mode)\t\(domain.url.path)")
            }
        case "inventory":
            for job in LaunchInventoryService().inventory() {
                let mode = job.isWritable ? "writable" : "read-only"
                print("\(job.label)\t\(job.domainName)\t\(mode)\t\(job.plistURL.path)")
            }
        case "tasks":
            for task in try LaunchDeckService().tasks() {
                print("\(task.id)\t\(task.title)\t\(task.label)")
            }
        case "create-interval":
            let parsed = try commandAfterSeparator(args)
            guard args.count >= 3, let seconds = Int(args[2]) else {
                throw CLIError.usage
            }
            let task = try ManagedTaskTemplate.interval(
                id: args[1],
                title: args[1],
                programArguments: parsed.command,
                everySeconds: seconds,
                workingDirectory: FileManager.default.currentDirectoryPath,
                environmentVariables: defaultEnvironment()
            )
            try save(task)
        case "create-calendar":
            let parsed = try commandAfterSeparator(args)
            guard args.count >= 4, let minute = Int(args[2]), let hour = Int(args[3]) else {
                throw CLIError.usage
            }
            let task = try ManagedTaskTemplate.calendar(
                id: args[1],
                title: args[1],
                programArguments: parsed.command,
                schedules: [CalendarSchedule(minute: minute, hour: hour)],
                workingDirectory: FileManager.default.currentDirectoryPath,
                environmentVariables: defaultEnvironment()
            )
            try save(task)
        case "create-one-shot":
            let parsed = try commandAfterSeparator(args)
            guard args.count >= 3, let timestamp = Double(args[2]) else {
                throw CLIError.usage
            }
            let task = try ManagedTaskTemplate.oneShot(
                id: args[1],
                title: args[1],
                programArguments: parsed.command,
                runAt: Date(timeIntervalSince1970: timestamp),
                workingDirectory: FileManager.default.currentDirectoryPath,
                environmentVariables: defaultEnvironment()
            )
            try save(task)
        case "load":
            try requireID(args) { try LaunchDeckService().load(id: $0) }
        case "unload":
            try requireID(args) { try LaunchDeckService().unload(id: $0) }
        case "run":
            try requireID(args) { try LaunchDeckService().runNow(id: $0) }
        case "enable":
            try requireID(args) { try LaunchDeckService().enable(id: $0) }
        case "disable":
            try requireID(args) { try LaunchDeckService().disable(id: $0) }
        case "status":
            guard args.count == 2 else { throw CLIError.usage }
            let snapshot = try LaunchDeckService().status(id: args[1])
            printStatus(snapshot)
        case "inspect":
            guard args.count == 3 else { throw CLIError.usage }
            printStatus(try Launchctl().status(label: args[1], plistURL: URL(filePath: args[2])))
        case "history":
            guard args.count == 2 else { throw CLIError.usage }
            for entry in try LaunchDeckService().history(id: args[1]) {
                print("\(entry.taskID)\t\(entry.action.rawValue)\t\(entry.exitCode)\t\(entry.occurredAt)")
            }
        case "log":
            guard args.count == 3, let stream = LogStream(rawValue: args[2]) else {
                throw CLIError.usage
            }
            print(try LaunchDeckService().logText(id: args[1], stream: stream), terminator: "")
        case "render-plist":
            guard args.count == 3 else { throw CLIError.usage }
            let outputURL = try renderPlist(metadataURL: URL(filePath: args[1]), outputURL: URL(filePath: args[2]))
            print(outputURL.path)
        case "version":
            print("\(LaunchDeck.appName) 0.1.0")
        default:
            throw CLIError.usage
        }
    }

    private static func save(_ task: ManagedTask) throws {
        try LaunchDeckService().save(task)
        print("\(task.id)\t\(task.label)\t\(task.standardOutPath)\t\(task.standardErrorPath)")
    }

    private static func requireID(_ args: [String], _ action: (String) throws -> CommandResult) throws {
        guard args.count == 2 else { throw CLIError.usage }
        let result = try action(args[1])
        print(result.standardOutput, terminator: "")
        print(result.standardError, terminator: "")
    }

    private static func commandAfterSeparator(_ args: [String]) throws -> (command: [String], separatorIndex: Int) {
        guard let separator = args.firstIndex(of: "--") else {
            throw CLIError.usage
        }

        let command = Array(args[(separator + 1)...])
        if command.isEmpty {
            throw CLIError.usage
        }

        return (command, separator)
    }

    private static func defaultEnvironment() -> [String: String] {
        ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]
    }

    private static func renderPlist(metadataURL: URL, outputURL: URL) throws -> URL {
        let task = try JSONDecoder().decode(ManagedTask.self, from: Data(contentsOf: metadataURL))
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try task.launchPlist().writeXML(to: outputURL, appOwned: true)
        return outputURL
    }

    private static func printStatus(_ snapshot: LaunchctlStatusSnapshot) {
        print("label=\(snapshot.label)")
        print("service_target=\(snapshot.serviceTarget)")
        print("plist_exists=\(snapshot.plistExists)")
        print("loaded=\(snapshot.loaded)")
        print("running_pid=\(snapshot.runningPID.map(String.init) ?? "nil")")
        print("last_exit_status=\(snapshot.lastExitStatus.map(String.init) ?? "nil")")
        print("disabled=\(snapshot.disabled.map(String.init) ?? "unknown")")
        print("raw_list_exit=\(snapshot.listResult.exitCode)")
        print("raw_print_exit=\(snapshot.printResult.exitCode)")
        print("raw_disabled_exit=\(snapshot.disabledResult.exitCode)")
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage

    var description: String {
        """
        Usage:
          launchdeck domains
          launchdeck inventory
          launchdeck tasks
          launchdeck create-interval <id> <seconds> -- <program> [args...]
          launchdeck create-calendar <id> <minute> <hour> -- <program> [args...]
          launchdeck create-one-shot <id> <unix-seconds> -- <program> [args...]
          launchdeck load|unload|run|enable|disable|status|history <id>
          launchdeck inspect <label> <plist-path>
          launchdeck log <id> <stdout|stderr>
          launchdeck render-plist <task-json> <plist-output>
          launchdeck version
        """
    }
}
