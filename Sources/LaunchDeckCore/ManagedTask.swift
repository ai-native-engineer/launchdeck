import Foundation

public struct LaunchDeckPaths: Equatable, Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var appSupportDirectory: URL {
        home.appending(path: "Library/Application Support/LaunchDeck", directoryHint: .isDirectory)
    }

    public var metadataDirectory: URL {
        appSupportDirectory.appending(path: "tasks", directoryHint: .isDirectory)
    }

    public var logDirectory: URL {
        home.appending(path: "Library/Logs/LaunchDeck", directoryHint: .isDirectory)
    }

    public func stdoutPath(taskID: String) -> String {
        logDirectory.appending(path: "\(taskID).stdout.log", directoryHint: .notDirectory).path
    }

    public func stderrPath(taskID: String) -> String {
        logDirectory.appending(path: "\(taskID).stderr.log", directoryHint: .notDirectory).path
    }
}

public enum ManagedTaskSchedule: Codable, Equatable, Sendable {
    case oneShot(Date)
    case calendar([CalendarSchedule])
    case interval(seconds: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case date
        case calendar
        case seconds
    }

    private enum Kind: String, Codable {
        case oneShot
        case calendar
        case interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .oneShot:
            self = .oneShot(try container.decode(Date.self, forKey: .date))
        case .calendar:
            self = .calendar(try container.decode([CalendarSchedule].self, forKey: .calendar))
        case .interval:
            self = .interval(seconds: try container.decode(Int.self, forKey: .seconds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .oneShot(date):
            try container.encode(Kind.oneShot, forKey: .type)
            try container.encode(date, forKey: .date)
        case let .calendar(calendar):
            try container.encode(Kind.calendar, forKey: .type)
            try container.encode(calendar, forKey: .calendar)
        case let .interval(seconds):
            try container.encode(Kind.interval, forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        }
    }
}

public enum AfterRunPolicy: String, Codable, Equatable, Sendable {
    case keep
    case disable
    case cleanupPlist
}

public struct ManagedTask: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var label: String
    public var programArguments: [String]
    public var workingDirectory: String?
    public var environmentVariables: [String: String]
    public var standardOutPath: String
    public var standardErrorPath: String
    public var timeoutSeconds: Int?
    public var schedule: ManagedTaskSchedule
    public var afterRunPolicy: AfterRunPolicy
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        label: String,
        programArguments: [String],
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        standardOutPath: String,
        standardErrorPath: String,
        timeoutSeconds: Int? = nil,
        schedule: ManagedTaskSchedule,
        afterRunPolicy: AfterRunPolicy,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.label = label
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.timeoutSeconds = timeoutSeconds
        self.schedule = schedule
        self.afterRunPolicy = afterRunPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func launchPlist(calendar: Calendar = Calendar(identifier: .gregorian)) throws -> LaunchPlist {
        try LaunchLabel.validateAppOwned(label)

        if programArguments.isEmpty {
            throw LaunchDeckError.missingExecutable(label)
        }

        let scheduleFields = try launchdSchedule(calendar: calendar)
        return LaunchPlist(
            label: label,
            programArguments: programArguments,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
            startInterval: scheduleFields.startInterval,
            startCalendarIntervals: scheduleFields.calendarIntervals,
            timeOut: timeoutSeconds,
            launchOnlyOnce: scheduleFields.launchOnlyOnce
        )
    }

    private func launchdSchedule(calendar: Calendar) throws -> (
        startInterval: Int?,
        calendarIntervals: [CalendarSchedule],
        launchOnlyOnce: Bool
    ) {
        switch schedule {
        case let .interval(seconds):
            if seconds <= 0 {
                throw LaunchDeckError.invalidSchedule("interval must be positive")
            }
            return (seconds, [], false)

        case let .calendar(schedules):
            if schedules.isEmpty {
                throw LaunchDeckError.invalidSchedule("calendar schedule must not be empty")
            }
            return (nil, schedules, false)

        case let .oneShot(date):
            if afterRunPolicy == .keep {
                throw LaunchDeckError.invalidSchedule("one-shot tasks must disable or clean up after running")
            }

            let components = calendar.dateComponents([.minute, .hour, .day, .month], from: date)
            let schedule = CalendarSchedule(
                minute: components.minute,
                hour: components.hour,
                day: components.day,
                month: components.month
            )
            return (nil, [schedule], true)
        }
    }
}

public enum ManagedTaskTemplate {
    public static func label(for id: String) throws -> String {
        let label = "\(LaunchDeck.labelPrefix).task.\(id)"
        try LaunchLabel.validateAppOwned(label)
        return label
    }

    public static func oneShot(
        id: String = UUID().uuidString,
        title: String,
        programArguments: [String],
        runAt: Date,
        paths: LaunchDeckPaths = LaunchDeckPaths(),
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        timeoutSeconds: Int? = nil,
        afterRunPolicy: AfterRunPolicy = .cleanupPlist
    ) throws -> ManagedTask {
        try task(
            id: id,
            title: title,
            programArguments: programArguments,
            paths: paths,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            timeoutSeconds: timeoutSeconds,
            schedule: .oneShot(runAt),
            afterRunPolicy: afterRunPolicy
        )
    }

    public static func calendar(
        id: String = UUID().uuidString,
        title: String,
        programArguments: [String],
        schedules: [CalendarSchedule],
        paths: LaunchDeckPaths = LaunchDeckPaths(),
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        timeoutSeconds: Int? = nil,
        afterRunPolicy: AfterRunPolicy = .keep
    ) throws -> ManagedTask {
        try task(
            id: id,
            title: title,
            programArguments: programArguments,
            paths: paths,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            timeoutSeconds: timeoutSeconds,
            schedule: .calendar(schedules),
            afterRunPolicy: afterRunPolicy
        )
    }

    public static func interval(
        id: String = UUID().uuidString,
        title: String,
        programArguments: [String],
        everySeconds: Int,
        paths: LaunchDeckPaths = LaunchDeckPaths(),
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        timeoutSeconds: Int? = nil,
        afterRunPolicy: AfterRunPolicy = .keep
    ) throws -> ManagedTask {
        try task(
            id: id,
            title: title,
            programArguments: programArguments,
            paths: paths,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            timeoutSeconds: timeoutSeconds,
            schedule: .interval(seconds: everySeconds),
            afterRunPolicy: afterRunPolicy
        )
    }

    private static func task(
        id: String,
        title: String,
        programArguments: [String],
        paths: LaunchDeckPaths,
        workingDirectory: String?,
        environmentVariables: [String: String],
        timeoutSeconds: Int?,
        schedule: ManagedTaskSchedule,
        afterRunPolicy: AfterRunPolicy
    ) throws -> ManagedTask {
        try ManagedTask(
            id: id,
            title: title,
            label: label(for: id),
            programArguments: programArguments,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            standardOutPath: paths.stdoutPath(taskID: id),
            standardErrorPath: paths.stderrPath(taskID: id),
            timeoutSeconds: timeoutSeconds,
            schedule: schedule,
            afterRunPolicy: afterRunPolicy
        )
    }
}

public struct ManagedTaskStore: Sendable {
    public let paths: LaunchDeckPaths

    public init(paths: LaunchDeckPaths = LaunchDeckPaths()) {
        self.paths = paths
    }

    public func save(_ task: ManagedTask, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: paths.metadataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(task)
        try data.write(to: metadataURL(for: task.id), options: .atomic)
    }

    public func load(id: String) throws -> ManagedTask {
        let decoder = JSONDecoder()
        return try decoder.decode(ManagedTask.self, from: Data(contentsOf: metadataURL(for: id)))
    }

    public func list(fileManager: FileManager = .default) throws -> [ManagedTask] {
        let urls = (
            try? fileManager.contentsOfDirectory(
                at: paths.metadataDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        ) ?? []

        return try urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                let decoder = JSONDecoder()
                return try decoder.decode(ManagedTask.self, from: Data(contentsOf: url))
            }
            .sorted { $0.title < $1.title }
    }

    public func metadataURL(for id: String) -> URL {
        paths.metadataDirectory.appending(path: "\(id).json", directoryHint: .notDirectory)
    }
}
