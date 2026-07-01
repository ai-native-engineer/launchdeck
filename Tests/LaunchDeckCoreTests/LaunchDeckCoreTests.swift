import XCTest
@testable import LaunchDeckCore

final class LaunchDeckCoreTests: XCTestCase {
    func testStandardDomainsMatchMVPBoundaries() {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        let domains = LaunchDomain.standard(home: home)

        XCTAssertEqual(domains.count, 5)
        XCTAssertEqual(domains.first?.url.path, "/Users/example/Library/LaunchAgents")
        XCTAssertEqual(domains.filter(\.allowsWrites).map(\.name), ["User LaunchAgents"])
        XCTAssertEqual(LaunchDeck.labelPrefix, "dev.seunan.launchdeck")
    }
}
