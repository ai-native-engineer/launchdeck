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
        XCTAssertTrue(inventory.last?.isAppOwned == true)
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

    func testManagedTaskTemplatesRoundTripThroughStore() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LaunchDeckPaths(home: root)
        let store = ManagedTaskStore(paths: paths)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let oneShot = try ManagedTaskTemplate.oneShot(
            id: "one",
            title: "One Shot",
            programArguments: ["/bin/echo", "once"],
            runAt: date,
            paths: paths,
            environmentVariables: ["PATH": "/usr/bin:/bin"],
            timeoutSeconds: 20
        )
        let calendar = try ManagedTaskTemplate.calendar(
            id: "calendar",
            title: "Calendar",
            programArguments: ["/bin/echo", "calendar"],
            schedules: [CalendarSchedule(minute: 15, hour: 9)],
            paths: paths
        )
        let interval = try ManagedTaskTemplate.interval(
            id: "interval",
            title: "Interval",
            programArguments: ["/bin/echo", "interval"],
            everySeconds: 300,
            paths: paths
        )

        try store.save(oneShot)
        try store.save(calendar)
        try store.save(interval)

        XCTAssertEqual(try store.load(id: "one"), oneShot)
        XCTAssertEqual(try store.list().map(\.id), ["calendar", "interval", "one"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: "interval").path))

        let oneShotPlist = try oneShot.launchPlist()
        XCTAssertEqual(oneShotPlist.environmentVariables["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(oneShotPlist.timeOut, 20)
        XCTAssertEqual(oneShotPlist.standardOutPath, paths.stdoutPath(taskID: "one"))
        XCTAssertEqual(oneShotPlist.standardErrorPath, paths.stderrPath(taskID: "one"))
        XCTAssertEqual(oneShotPlist.startCalendarIntervals.count, 1)
        XCTAssertTrue(oneShotPlist.launchOnlyOnce)

        let intervalPlist = try interval.launchPlist()
        XCTAssertEqual(intervalPlist.startInterval, 300)
    }

    func testManagedTaskGeneratedLaunchAgentPlistLints() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LaunchDeckPaths(home: root)
        let task = try ManagedTaskTemplate.interval(
            id: "lint",
            title: "Lint",
            programArguments: ["/bin/echo", "lint"],
            everySeconds: 60,
            paths: paths,
            workingDirectory: "/tmp",
            environmentVariables: ["PATH": "/usr/bin:/bin"],
            timeoutSeconds: 10
        )
        let plistURL = try LaunchAgentPlistStore(home: root).write(try task.launchPlist())

        XCTAssertTrue(try PlistLinter().lint(plistURL).succeeded)
    }

    func testOneShotTasksMustDisableOrCleanupToAvoidYearlyCalendarRepeats() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = try ManagedTaskTemplate.oneShot(
            id: "unsafe",
            title: "Unsafe",
            programArguments: ["/bin/echo", "unsafe"],
            runAt: Date(timeIntervalSince1970: 1_800_000_000),
            paths: LaunchDeckPaths(home: root),
            afterRunPolicy: .keep
        )

        XCTAssertThrowsError(try task.launchPlist())
    }

    func testLaunchDeckServiceRunsTaskLifecycleThroughSharedCore() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var calls: [[String]] = []
        let runner = CommandRunner { executable, arguments in
            calls.append([executable] + arguments)
            return CommandResult(exitCode: 0, standardOutput: "ok\n")
        }
        let paths = LaunchDeckPaths(home: root)
        let service = LaunchDeckService(paths: paths, runner: runner, uid: 501)
        let task = try ManagedTaskTemplate.interval(
            id: "svc",
            title: "Service",
            programArguments: ["/bin/echo", "service"],
            everySeconds: 60,
            paths: paths
        )

        try service.save(task)
        try service.load(id: "svc")
        try service.runNow(id: "svc")
        try service.enable(id: "svc")
        try service.disable(id: "svc")
        try service.unload(id: "svc")
        _ = try service.status(id: "svc")

        let plistPath = root.appending(path: "Library/LaunchAgents/dev.seunan.launchdeck.task.svc.plist").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath))
        XCTAssertEqual(calls, [
            ["/usr/bin/env", "plutil", "-lint", plistPath],
            ["/usr/bin/env", "launchctl", "bootstrap", "gui/501", plistPath],
            ["/usr/bin/env", "launchctl", "kickstart", "-kp", "gui/501/dev.seunan.launchdeck.task.svc"],
            ["/usr/bin/env", "launchctl", "enable", "gui/501/dev.seunan.launchdeck.task.svc"],
            ["/usr/bin/env", "launchctl", "disable", "gui/501/dev.seunan.launchdeck.task.svc"],
            ["/usr/bin/env", "launchctl", "bootout", "gui/501", plistPath],
            ["/usr/bin/env", "launchctl", "print", "gui/501/dev.seunan.launchdeck.task.svc"],
            ["/usr/bin/env", "launchctl", "print-disabled", "gui/501"],
        ])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LaunchDeckTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
