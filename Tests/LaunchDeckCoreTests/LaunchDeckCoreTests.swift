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

    func testGeneratedAppOwnedPlistRoundTripsAndLints() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let plist = LaunchPlist(
            label: "dev.seunan.launchdeck.test",
            programArguments: ["/bin/echo", "hello"],
            workingDirectory: "/tmp",
            environmentVariables: ["PATH": "/usr/bin:/bin"],
            standardOutPath: root.appending(path: "stdout.log").path,
            standardErrorPath: root.appending(path: "stderr.log").path,
            startInterval: 60,
            timeOut: 30,
            launchOnlyOnce: true,
            runAtLoad: true
        )

        let store = LaunchAgentPlistStore(home: root)
        let url = try store.write(plist)
        let parsed = try LaunchPlist.read(from: url)

        XCTAssertEqual(parsed, plist)
        XCTAssertTrue(try PlistLinter().lint(url).succeeded)
    }

    func testInventoryParsesReadablePlistsAndMarksOnlyUserAgentsWritable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let userDirectory = root.appending(path: "user", directoryHint: .isDirectory)
        let systemDirectory = root.appending(path: "system", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)

        try LaunchPlist(label: "dev.seunan.launchdeck.inventory", programArguments: ["/bin/echo", "user"])
            .writeXML(to: userDirectory.appending(path: "dev.seunan.launchdeck.inventory.plist"))
        try LaunchPlist(label: "com.example.system", programArguments: ["/bin/echo", "system"])
            .writeXML(to: systemDirectory.appending(path: "com.example.system.plist"))

        let inventory = LaunchInventoryService(domains: [
            .userAgents(userDirectory),
            .systemDaemons(systemDirectory),
        ]).inventory()

        XCTAssertEqual(inventory.map(\.label), ["com.example.system", "dev.seunan.launchdeck.inventory"])
        XCTAssertEqual(inventory.first?.isWritable, false)
        XCTAssertEqual(inventory.last?.isWritable, true)
        XCTAssertEqual(inventory.last?.programArguments, ["/bin/echo", "user"])
    }

    func testLaunchctlUsesGuiDomainSafeArgv() throws {
        var calls: [[String]] = []
        let runner = CommandRunner { executable, arguments in
            calls.append([executable] + arguments)
            return CommandResult(exitCode: 0, standardOutput: "ok")
        }
        let launchctl = Launchctl(uid: 501, runner: runner)
        let label = "dev.seunan.launchdeck.test"
        let plistURL = URL(filePath: "/tmp/dev.seunan.launchdeck.test.plist")

        _ = try launchctl.bootstrap(plistURL: plistURL)
        _ = try launchctl.bootout(plistURL: plistURL)
        _ = try launchctl.enable(label: label)
        _ = try launchctl.disable(label: label)
        _ = try launchctl.kickstart(label: label)
        _ = try launchctl.status(label: label)

        XCTAssertEqual(calls, [
            ["/usr/bin/env", "launchctl", "bootstrap", "gui/501", "/tmp/dev.seunan.launchdeck.test.plist"],
            ["/usr/bin/env", "launchctl", "bootout", "gui/501", "/tmp/dev.seunan.launchdeck.test.plist"],
            ["/usr/bin/env", "launchctl", "enable", "gui/501/dev.seunan.launchdeck.test"],
            ["/usr/bin/env", "launchctl", "disable", "gui/501/dev.seunan.launchdeck.test"],
            ["/usr/bin/env", "launchctl", "kickstart", "-kp", "gui/501/dev.seunan.launchdeck.test"],
            ["/usr/bin/env", "launchctl", "print", "gui/501/dev.seunan.launchdeck.test"],
            ["/usr/bin/env", "launchctl", "print-disabled", "gui/501"],
        ])
    }

    func testWriteAndServiceTargetsRejectUnsafeLabels() throws {
        let store = LaunchAgentPlistStore(home: URL(filePath: "/tmp", directoryHint: .isDirectory))
        XCTAssertThrowsError(try store.plistURL(for: "com.example.other"))
        XCTAssertThrowsError(try Launchctl(uid: 501).serviceTarget(for: "bad/label"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LaunchDeckTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
