import Foundation

public enum LaunchDeck {
    public static let appName = "LaunchDeck"
    public static let labelPrefix = "dev.seunan.launchdeck"
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
    public var id: String { label }

    public let label: String
    public let plistURL: URL
    public let domainName: String
    public let isWritable: Bool

    public init(label: String, plistURL: URL, domainName: String, isWritable: Bool) {
        self.label = label
        self.plistURL = plistURL
        self.domainName = domainName
        self.isWritable = isWritable
    }
}

public struct LaunchInventoryService: Sendable {
    public let domains: [LaunchDomain]

    public init(domains: [LaunchDomain] = LaunchDomain.standard()) {
        self.domains = domains
    }

    public func inventory() -> [LaunchJobSummary] {
        []
    }
}
