import Foundation

public struct CalendarSchedule: Codable, Equatable, Sendable {
    public let minute: Int?
    public let hour: Int?
    public let day: Int?
    public let month: Int?
    public let weekday: Int?

    public init(minute: Int? = nil, hour: Int? = nil, day: Int? = nil, month: Int? = nil, weekday: Int? = nil) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.month = month
        self.weekday = weekday
    }

    public init?(propertyList: [String: Any]) {
        let schedule = CalendarSchedule(
            minute: Self.intValue(propertyList["Minute"]),
            hour: Self.intValue(propertyList["Hour"]),
            day: Self.intValue(propertyList["Day"]),
            month: Self.intValue(propertyList["Month"]),
            weekday: Self.intValue(propertyList["Weekday"])
        )

        if schedule.propertyList.isEmpty {
            return nil
        }

        self = schedule
    }

    public var propertyList: [String: Int] {
        var values: [String: Int] = [:]
        values["Minute"] = minute
        values["Hour"] = hour
        values["Day"] = day
        values["Month"] = month
        values["Weekday"] = weekday
        return values
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }
}

public struct LaunchPlist: Equatable, Sendable {
    public let label: String
    public let program: String?
    public let programArguments: [String]
    public let workingDirectory: String?
    public let environmentVariables: [String: String]
    public let standardOutPath: String?
    public let standardErrorPath: String?
    public let startInterval: Int?
    public let startCalendarIntervals: [CalendarSchedule]
    public let timeOut: Int?
    public let launchOnlyOnce: Bool
    public let runAtLoad: Bool

    public init(
        label: String,
        program: String? = nil,
        programArguments: [String] = [],
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        startInterval: Int? = nil,
        startCalendarIntervals: [CalendarSchedule] = [],
        timeOut: Int? = nil,
        launchOnlyOnce: Bool = false,
        runAtLoad: Bool = false
    ) {
        self.label = label
        self.program = program
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.startInterval = startInterval
        self.startCalendarIntervals = startCalendarIntervals
        self.timeOut = timeOut
        self.launchOnlyOnce = launchOnlyOnce
        self.runAtLoad = runAtLoad
    }

    public static func read(from url: URL) throws -> LaunchPlist {
        let data = try Data(contentsOf: url)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = dictionary["Label"] as? String
        else {
            throw LaunchDeckError.invalidPlist(url)
        }

        return LaunchPlist(
            label: label,
            program: dictionary["Program"] as? String,
            programArguments: Self.stringArray(dictionary["ProgramArguments"]),
            workingDirectory: dictionary["WorkingDirectory"] as? String,
            environmentVariables: Self.stringDictionary(dictionary["EnvironmentVariables"]),
            standardOutPath: dictionary["StandardOutPath"] as? String,
            standardErrorPath: dictionary["StandardErrorPath"] as? String,
            startInterval: Self.intValue(dictionary["StartInterval"]),
            startCalendarIntervals: Self.calendarIntervals(dictionary["StartCalendarInterval"]),
            timeOut: Self.intValue(dictionary["TimeOut"]),
            launchOnlyOnce: Self.boolValue(dictionary["LaunchOnlyOnce"]) ?? false,
            runAtLoad: Self.boolValue(dictionary["RunAtLoad"]) ?? false
        )
    }

    public func propertyList(appOwned: Bool = false) throws -> [String: Any] {
        if appOwned {
            try LaunchLabel.validateAppOwned(label)
        } else {
            try LaunchLabel.validateServiceLabel(label)
        }

        if program == nil && programArguments.isEmpty {
            throw LaunchDeckError.missingExecutable(label)
        }

        var dictionary: [String: Any] = ["Label": label]
        dictionary["Program"] = program

        if !programArguments.isEmpty {
            dictionary["ProgramArguments"] = programArguments
        }

        dictionary["WorkingDirectory"] = workingDirectory

        if !environmentVariables.isEmpty {
            dictionary["EnvironmentVariables"] = environmentVariables
        }

        dictionary["StandardOutPath"] = standardOutPath
        dictionary["StandardErrorPath"] = standardErrorPath
        dictionary["StartInterval"] = startInterval

        if startCalendarIntervals.count == 1 {
            dictionary["StartCalendarInterval"] = startCalendarIntervals[0].propertyList
        } else if !startCalendarIntervals.isEmpty {
            dictionary["StartCalendarInterval"] = startCalendarIntervals.map(\.propertyList)
        }

        dictionary["TimeOut"] = timeOut

        if launchOnlyOnce {
            dictionary["LaunchOnlyOnce"] = true
        }

        if runAtLoad {
            dictionary["RunAtLoad"] = true
        }

        return dictionary
    }

    public func xmlData(appOwned: Bool = false) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: propertyList(appOwned: appOwned),
            format: .xml,
            options: 0
        )
    }

    public func writeXML(to url: URL, appOwned: Bool = false) throws {
        let data = try xmlData(appOwned: appOwned)
        try data.write(to: url, options: .atomic)
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }

        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func stringDictionary(_ value: Any?) -> [String: String] {
        if let values = value as? [String: String] {
            return values
        }

        guard let values = value as? [String: Any] else {
            return [:]
        }

        return values.compactMapValues { $0 as? String }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private static func calendarIntervals(_ value: Any?) -> [CalendarSchedule] {
        if let dictionary = value as? [String: Any] {
            return CalendarSchedule(propertyList: dictionary).map { [$0] } ?? []
        }

        return (value as? [[String: Any]])?.compactMap(CalendarSchedule.init(propertyList:)) ?? []
    }
}

public struct LaunchAgentPlistStore: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var directory: URL {
        home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    public func plistURL(for label: String) throws -> URL {
        try LaunchLabel.validateAppOwned(label)
        return directory.appending(path: "\(label).plist", directoryHint: .notDirectory)
    }

    @discardableResult
    public func write(_ plist: LaunchPlist, fileManager: FileManager = .default) throws -> URL {
        let url = try plistURL(for: plist.label)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try plist.writeXML(to: url, appOwned: true)
        return url
    }
}
