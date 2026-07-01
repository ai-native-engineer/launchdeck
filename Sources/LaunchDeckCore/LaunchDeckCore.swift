import Foundation

public enum LaunchDeck {
    public static let appName = "LaunchDeck"
    public static let labelPrefix = "io.github.launchdeck"
}

public enum LaunchDeckError: Error, CustomStringConvertible, LocalizedError {
    case invalidLabel(String)
    case nonAppOwnedLabel(String)
    case missingExecutable(String)
    case invalidSchedule(String)
    case commandFailed(String, CommandResult)
    case unsafePath(URL)
    case invalidPlist(URL)

    public var description: String {
        switch self {
        case let .invalidLabel(label):
            "Invalid launchd label: \(label)"
        case let .nonAppOwnedLabel(label):
            "Label is not app-owned: \(label)"
        case let .missingExecutable(label):
            "LaunchAgent has neither Program nor ProgramArguments: \(label)"
        case let .invalidSchedule(message):
            "Invalid schedule: \(message)"
        case let .commandFailed(command, result):
            "\(command) failed with exit \(result.exitCode): \(result.standardError)"
        case let .unsafePath(url):
            "Path is outside LaunchDeck-owned locations: \(url.path)"
        case let .invalidPlist(url):
            "Invalid launchd plist: \(url.path)"
        }
    }

    public var errorDescription: String? { description }
}

public enum LaunchLabel {
    public static func validateServiceLabel(_ label: String) throws {
        if label.isEmpty || label.contains("/") || label.contains("\0") {
            throw LaunchDeckError.invalidLabel(label)
        }
    }

    public static func validateAppOwned(_ label: String) throws {
        try validateServiceLabel(label)
        if !label.hasPrefix(LaunchDeck.labelPrefix + ".") {
            throw LaunchDeckError.nonAppOwnedLabel(label)
        }
    }
}

public enum LaunchDomain: Equatable, Sendable {
    case userAgents(URL)
    case localAgents(URL)
    case localDaemons(URL)
    case systemAgents(URL)
    case systemDaemons(URL)

    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LaunchDomain] {
        [
            .userAgents(home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)),
            .localAgents(URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory)),
            .localDaemons(URL(filePath: "/Library/LaunchDaemons", directoryHint: .isDirectory)),
            .systemAgents(URL(filePath: "/System/Library/LaunchAgents", directoryHint: .isDirectory)),
            .systemDaemons(URL(filePath: "/System/Library/LaunchDaemons", directoryHint: .isDirectory)),
        ]
    }

    public var name: String {
        switch self {
        case .userAgents:
            "User LaunchAgents"
        case .localAgents:
            "Local LaunchAgents"
        case .localDaemons:
            "Local LaunchDaemons"
        case .systemAgents:
            "System LaunchAgents"
        case .systemDaemons:
            "System LaunchDaemons"
        }
    }

    public var url: URL {
        switch self {
        case let .userAgents(url),
             let .localAgents(url),
             let .localDaemons(url),
             let .systemAgents(url),
             let .systemDaemons(url):
            url
        }
    }

    public var allowsWrites: Bool {
        if case .userAgents = self {
            true
        } else {
            false
        }
    }
}

public struct LaunchJobSummary: Equatable, Identifiable, Sendable {
    public var id: String { plistURL.path }

    public let label: String
    public let plistURL: URL
    public let domainName: String
    public let isWritable: Bool
    public let program: String?
    public let programArguments: [String]
    public let standardOutPath: String?
    public let standardErrorPath: String?
    public let parseError: String?
    public var isAppOwned: Bool { label.hasPrefix(LaunchDeck.labelPrefix + ".") }

    public init(
        label: String,
        plistURL: URL,
        domainName: String,
        isWritable: Bool,
        program: String? = nil,
        programArguments: [String] = [],
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        parseError: String? = nil
    ) {
        self.label = label
        self.plistURL = plistURL
        self.domainName = domainName
        self.isWritable = isWritable
        self.program = program
        self.programArguments = programArguments
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.parseError = parseError
    }
}

public struct LaunchInventoryService: Sendable {
    public let domains: [LaunchDomain]

    public init(domains: [LaunchDomain] = LaunchDomain.standard()) {
        self.domains = domains
    }

    public func inventory(fileManager: FileManager = .default) -> [LaunchJobSummary] {
        domains.flatMap { domain in
            let urls = (
                try? fileManager.contentsOfDirectory(
                    at: domain.url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            ) ?? []

            return urls
                .filter { $0.pathExtension == "plist" }
                .map { url in
                    do {
                        let plist = try LaunchPlist.read(from: url)
                        return LaunchJobSummary(
                            label: plist.label,
                            plistURL: url,
                            domainName: domain.name,
                            isWritable: domain.allowsWrites,
                            program: plist.program,
                            programArguments: plist.programArguments,
                            standardOutPath: plist.standardOutPath,
                            standardErrorPath: plist.standardErrorPath
                        )
                    } catch {
                        return LaunchJobSummary(
                            label: url.deletingPathExtension().lastPathComponent,
                            plistURL: url,
                            domainName: domain.name,
                            isWritable: domain.allowsWrites,
                            parseError: String(describing: error)
                        )
                    }
                }
        }
        .sorted { lhs, rhs in
            if lhs.domainName == rhs.domainName {
                lhs.label < rhs.label
            } else {
                lhs.domainName < rhs.domainName
            }
        }
    }
}
