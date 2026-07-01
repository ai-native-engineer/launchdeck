import Foundation

public enum LogStream: String, Sendable {
    case stdout
    case stderr
}

public struct LaunchDeckService {
    public let paths: LaunchDeckPaths
    public let store: ManagedTaskStore
    public let agentStore: LaunchAgentPlistStore
    public let linter: PlistLinter
    public let launchctl: Launchctl

    public init(paths: LaunchDeckPaths = LaunchDeckPaths(), runner: CommandRunner = .live, uid: Int = Int(getuid())) {
        self.paths = paths
        self.store = ManagedTaskStore(paths: paths)
        self.agentStore = LaunchAgentPlistStore(home: paths.home)
        self.linter = PlistLinter(runner: runner)
        self.launchctl = Launchctl(uid: uid, runner: runner)
    }

    public func tasks() throws -> [ManagedTask] {
        try store.list()
    }

    public func save(_ task: ManagedTask) throws {
        try store.save(task)
    }

    @discardableResult
    public func installPlist(id: String) throws -> URL {
        let task = try store.load(id: id)
        let url = try agentStore.write(try task.launchPlist())
        try requireSuccess("plutil -lint", linter.lint(url))
        return url
    }

    @discardableResult
    public func load(id: String) throws -> CommandResult {
        let url = try installPlist(id: id)
        return try requireSuccess("launchctl bootstrap", launchctl.bootstrap(plistURL: url))
    }

    @discardableResult
    public func unload(id: String) throws -> CommandResult {
        let task = try store.load(id: id)
        let url = try agentStore.plistURL(for: task.label)
        return try requireSuccess("launchctl bootout", launchctl.bootout(plistURL: url))
    }

    @discardableResult
    public func runNow(id: String) throws -> CommandResult {
        let task = try store.load(id: id)
        return try requireSuccess("launchctl kickstart", launchctl.kickstart(label: task.label))
    }

    @discardableResult
    public func enable(id: String) throws -> CommandResult {
        let task = try store.load(id: id)
        return try requireSuccess("launchctl enable", launchctl.enable(label: task.label))
    }

    @discardableResult
    public func disable(id: String) throws -> CommandResult {
        let task = try store.load(id: id)
        return try requireSuccess("launchctl disable", launchctl.disable(label: task.label))
    }

    public func status(id: String) throws -> LaunchctlStatusSnapshot {
        let task = try store.load(id: id)
        return try launchctl.status(label: task.label)
    }

    public func logText(id: String, stream: LogStream) throws -> String {
        let task = try store.load(id: id)
        let path = stream == .stdout ? task.standardOutPath : task.standardErrorPath
        let url = URL(filePath: path)

        if !FileManager.default.fileExists(atPath: url.path) {
            return ""
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    private func requireSuccess(_ command: String, _ result: CommandResult) throws -> CommandResult {
        if !result.succeeded {
            throw LaunchDeckError.commandFailed(command, result)
        }
        return result
    }
}
