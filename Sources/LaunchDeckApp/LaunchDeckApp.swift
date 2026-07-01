import AppKit
import LaunchDeckCore
import SwiftUI

@main
struct LaunchDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        openMainWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func openMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaunchDeck"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LaunchDeckContentView())
        placeOnMainScreen(window)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func placeOnMainScreen(_ window: NSWindow) {
        guard let frame = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }

        let size = NSSize(width: min(1180, frame.width - 80), height: min(720, frame.height - 80))
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private struct LaunchDeckContentView: View {
    @State private var jobs = LaunchInventoryService().inventory()
    @State private var selection: String?
    @State private var searchText = ""
    @State private var filter = JobFilter.attention

    private var selectedJob: LaunchJobSummary? {
        jobs.first { $0.id == selection }
    }

    private var visibleJobs: [LaunchJobSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return jobs.filter { job in
            matches(filter, job: job) && (query.isEmpty || matchesSearch(query, job: job))
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("LaunchDeck")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        jobs = LaunchInventoryService().inventory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("새로고침")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                TextField("라벨, 앱, 경로 검색", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                FilterTabs(filter: $filter, jobs: jobs)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                Divider()

                ScrollView {
                    if visibleJobs.isEmpty {
                        ContentUnavailableView("표시할 항목 없음", systemImage: "tray")
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleJobs) { job in
                                JobRow(job: job, isSelected: job.id == selection) {
                                    selection = job.id
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)

            Group {
                if let job = selectedJob {
                    JobDetailView(
                        job: job,
                        onInventoryChanged: {
                            jobs = LaunchInventoryService().inventory()
                        }
                    )
                        .id(job.id)
                } else {
                    ContentUnavailableView("항목을 선택하세요", systemImage: "list.bullet.rectangle")
                }
            }
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            ensureSelection()
        }
        .onChange(of: filter) { _, _ in
            ensureSelection()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelection()
        }
        .onChange(of: jobs) { _, _ in
            ensureSelection()
        }
    }

    private func ensureSelection() {
        if let selection, visibleJobs.contains(where: { $0.id == selection }) {
            return
        }

        selection = visibleJobs.first?.id
    }
}

private enum JobFilter: String, CaseIterable, Identifiable {
    case attention
    case mine
    case external
    case apple
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention:
            "주의 필요"
        case .mine:
            "내 자동화"
        case .external:
            "외부 앱"
        case .apple:
            "Apple 시스템"
        case .all:
            "전체"
        }
    }
}

private struct FilterTabs: View {
    @Binding var filter: JobFilter
    let jobs: [LaunchJobSummary]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(JobFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    HStack {
                        Text(item.title)
                            .lineLimit(1)
                        Spacer()
                        Text("\(jobs.filter { matches(item, job: $0) }.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(filter == item ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct JobRow: View {
    let job: LaunchJobSummary
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: rowIconName(for: job))
                    .foregroundStyle(rowIconColor(for: job))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("\(serviceOwner(for: job)) · \(koreanDomain(job.domainName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct JobDetailView: View {
    let job: LaunchJobSummary
    let onInventoryChanged: () -> Void

    @State private var plist: LaunchPlist?
    @State private var status: LaunchctlStatusSnapshot?
    @State private var errorText = ""
    @State private var rawDiagnostic = ""
    @State private var editor = PlistEditorState()
    @State private var stdoutLog = ""
    @State private var stderrLog = ""

    private var canControl: Bool {
        job.isWritable && isPersonalAutomation(job) && !isAppleSystem(job) && job.parseError == nil
    }

    private var canEdit: Bool {
        canControl && plist != nil && job.parseError == nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("detail-top")

                VStack(alignment: .leading, spacing: 18) {
                    header
                    controlSection

                    if !canControl {
                        notice("읽기 전용", "내 자동화로 분류된 사용자 LaunchAgent만 편집, 실행, 활성화, 비활성화를 허용합니다.")
                    }

                    editorSection
                    logSection
                    commandSection
                    scheduleSection

                    if !rawDiagnostic.isEmpty {
                        textSection("원본 진단", rawDiagnostic)
                    }

                    if !errorText.isEmpty {
                        notice("오류", errorText)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                loadDetails()
                scrollToTop(proxy)
            }
            .onChange(of: job.id) { _, _ in
                loadDetails()
                scrollToTop(proxy)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.label)
                .font(.system(size: 28, weight: .semibold))
                .textSelection(.enabled)
            Text(job.plistURL.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                tagPill(koreanDomain(job.domainName))
                tagPill(ownershipTag(for: job))
                tagPill(canControl ? "편집 가능" : "읽기 전용")
            }
        }
    }

    private var controlSection: some View {
        section("상태 및 작업") {
            InfoGrid(rows: [
                ("plist 파일", plistExistsText),
                ("launchd 로드", loadedText),
                ("실행 PID", runningPIDText),
                ("비활성화", disabledText),
                ("마지막 종료 코드", lastExitStatusText),
            ])

            HStack {
                Button("지금 실행") { runNow() }
                Button("로드") { run("로드") { try Launchctl().bootstrap(plistURL: job.plistURL) } }
                Button("언로드") { run("언로드") { try Launchctl().bootout(plistURL: job.plistURL) } }
                Button("활성화") { run("활성화") { try Launchctl().enable(label: job.label) } }
                Button("비활성화") { run("비활성화") { try Launchctl().disable(label: job.label) } }
            }
            .disabled(!canControl)

            HStack {
                Button("상태 새로고침") { refreshStatus() }
                Button("원본 진단 보기") { showRawDiagnostic() }
            }
        }
    }

    private var editorSection: some View {
        section("편집기") {
            VStack(alignment: .leading, spacing: 12) {
                EditorField(title: "Program", text: $editor.program, placeholder: "없음")
                    .disabled(!canEdit)
                EditorTextArea(title: "ProgramArguments", text: $editor.arguments, height: 86)
                    .disabled(!canEdit)
                EditorField(title: "WorkingDirectory", text: $editor.workingDirectory, placeholder: "기본값")
                    .disabled(!canEdit)
                EditorTextArea(title: "EnvironmentVariables", text: $editor.environment, height: 70)
                    .disabled(!canEdit)
                EditorField(title: "StandardOutPath", text: $editor.standardOutPath, placeholder: "없음")
                    .disabled(!canEdit)
                EditorField(title: "StandardErrorPath", text: $editor.standardErrorPath, placeholder: "없음")
                    .disabled(!canEdit)

                HStack {
                    Button("저장") { saveEditor() }
                        .disabled(!canEdit)
                    Button("원본 다시 읽기") { loadDetails() }
                    Spacer()
                    Text("인자와 환경 변수는 한 줄에 하나씩 입력")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var commandSection: some View {
        section("실행 명령") {
            InfoGrid(rows: [
                ("실행 파일", executableText),
                ("인자", argumentsText),
                ("작업 폴더", plist?.workingDirectory ?? "기본값"),
                ("환경 변수", environmentText),
                ("타임아웃", plist?.timeOut.map { "\($0)초" } ?? "없음"),
            ])
        }
    }

    private var scheduleSection: some View {
        section("스케줄") {
            InfoGrid(rows: [
                ("종류", scheduleKind),
                ("상세", scheduleText),
                ("시작 시 실행", plist?.runAtLoad == true ? "예" : "아니오"),
                ("한 번만 실행", plist?.launchOnlyOnce == true ? "예" : "아니오"),
            ])
        }
    }

    private var logSection: some View {
        section("로그") {
            InfoGrid(rows: [
                ("표준 출력", plist?.standardOutPath ?? "없음"),
                ("표준 에러", plist?.standardErrorPath ?? "없음"),
            ])

            HStack {
                Button("표준 출력 보기") { stdoutLog = logTail(path: plist?.standardOutPath) }
                    .disabled(plist?.standardOutPath == nil)
                Button("표준 에러 보기") { stderrLog = logTail(path: plist?.standardErrorPath) }
                    .disabled(plist?.standardErrorPath == nil)
                Button("표준 출력 파일 열기") { openPath(plist?.standardOutPath) }
                    .disabled(plist?.standardOutPath == nil)
                Button("표준 에러 파일 열기") { openPath(plist?.standardErrorPath) }
                    .disabled(plist?.standardErrorPath == nil)
            }

            if !stdoutLog.isEmpty {
                LogPreview(title: "표준 출력", text: stdoutLog)
            }
            if !stderrLog.isEmpty {
                LogPreview(title: "표준 에러", text: stderrLog)
            }
        }
    }

    private var executableText: String {
        if let program = plist?.program {
            return program
        }
        return plist?.programArguments.first ?? "없음"
    }

    private var argumentsText: String {
        let arguments = Array((plist?.programArguments ?? []).dropFirst())
        return arguments.isEmpty ? "없음" : arguments.joined(separator: " ")
    }

    private var environmentText: String {
        let values = plist?.environmentVariables ?? [:]
        if values.isEmpty {
            return "없음"
        }
        return values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private var scheduleKind: String {
        guard let plist else {
            return "알 수 없음"
        }
        if plist.startInterval != nil {
            return "반복 간격"
        }
        if !plist.startCalendarIntervals.isEmpty {
            return plist.launchOnlyOnce ? "예약 1회 실행" : "달력 기반 반복"
        }
        if plist.runAtLoad {
            return "로드 시 실행"
        }
        return "요청 시 실행"
    }

    private var scheduleText: String {
        guard let plist else {
            return "읽을 수 없음"
        }
        if let interval = plist.startInterval {
            return "\(interval)초마다 실행"
        }
        if !plist.startCalendarIntervals.isEmpty {
            return plist.startCalendarIntervals.map(calendarScheduleText).joined(separator: "\n")
        }
        return "명시된 스케줄 없음"
    }

    private var plistExistsText: String {
        if let status {
            return status.plistExists ? "있음" : "없음"
        }

        return FileManager.default.fileExists(atPath: job.plistURL.path) ? "있음" : "없음"
    }

    private var loadedText: String {
        guard let status else {
            return "상태 새로고침 전"
        }

        return status.loaded ? "로드됨" : "로드 안 됨"
    }

    private var runningPIDText: String {
        guard let status else {
            return "상태 새로고침 전"
        }

        return status.runningPID.map(String.init) ?? "실행 중 아님"
    }

    private var disabledText: String {
        guard let status else {
            return "상태 새로고침 전"
        }

        return boolText(status.disabled)
    }

    private var lastExitStatusText: String {
        guard let status else {
            return "상태 새로고침 전"
        }

        return status.lastExitStatus.map(String.init) ?? "없음"
    }

    private func loadDetails() {
        errorText = ""
        rawDiagnostic = ""
        status = nil

        do {
            let loadedPlist = try LaunchPlist.read(from: job.plistURL)
            plist = loadedPlist
            editor = PlistEditorState(plist: loadedPlist)
            stdoutLog = ""
            stderrLog = ""
            refreshStatus()
        } catch {
            plist = nil
            editor = PlistEditorState()
            stdoutLog = ""
            stderrLog = ""
            errorText = "plist를 읽을 수 없습니다: \(error)"
        }
    }

    private func refreshStatus() {
        do {
            status = try Launchctl().status(label: job.label, plistURL: job.plistURL)
            rawDiagnostic = ""
        } catch {
            status = nil
            if errorText.isEmpty {
                errorText = "상태를 읽을 수 없습니다: \(error)"
            }
        }
    }

    private func saveEditor() {
        guard canEdit, let plist else {
            return
        }

        let tempURL = job.plistURL
            .deletingLastPathComponent()
            .appending(path: ".\(job.plistURL.lastPathComponent).launchdeck-tmp")

        do {
            let updated = try editor.launchPlist(label: plist.label, preserving: plist)
            let data = try updated.xmlData()
            try data.write(to: tempURL, options: .atomic)

            let lint = try PlistLinter().lint(tempURL)
            guard lint.succeeded else {
                throw LaunchDeckError.commandFailed("plutil -lint", lint)
            }

            try data.write(to: job.plistURL, options: .atomic)
            try? FileManager.default.removeItem(at: tempURL)
            self.plist = updated
            editor = PlistEditorState(plist: updated)
            stdoutLog = ""
            stderrLog = ""
            onInventoryChanged()
            errorText = "저장됨: plutil -lint 통과"
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            errorText = "저장 실패: \(error)"
        }
    }

    private func run(_ name: String, action: () throws -> CommandResult) {
        do {
            let result = try action()
            errorText = "\(name): 종료 코드 \(result.exitCode)"
            refreshStatus()
        } catch {
            errorText = "\(name): \(error)"
        }
    }

    private func runNow() {
        do {
            let launchctl = Launchctl()
            let snapshot = try launchctl.status(label: job.label, plistURL: job.plistURL)

            if snapshot.loaded {
                let bootout = try launchctl.bootout(plistURL: job.plistURL)
                guard bootout.succeeded else {
                    throw LaunchDeckError.commandFailed("launchctl bootout", bootout)
                }
            }

            let bootstrap = try launchctl.bootstrap(plistURL: job.plistURL)
            guard bootstrap.succeeded else {
                throw LaunchDeckError.commandFailed("launchctl bootstrap", bootstrap)
            }

            let kickstart = try launchctl.kickstart(label: job.label)
            errorText = "지금 실행: 종료 코드 \(kickstart.exitCode)"
            refreshStatus()
        } catch {
            errorText = "지금 실행: \(error)"
        }
    }

    private func showRawDiagnostic() {
        do {
            let snapshot = try Launchctl().status(label: job.label, plistURL: job.plistURL)
            status = snapshot
            rawDiagnostic = snapshot.rawDiagnosticOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawDiagnostic.isEmpty {
                rawDiagnostic = "원본 진단 출력이 없습니다."
            }
        } catch {
            errorText = "원본 진단을 읽을 수 없습니다: \(error)"
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("detail-top", anchor: .top)
        }
    }

    private func openPath(_ path: String?) {
        guard let path else {
            return
        }
        NSWorkspace.shared.open(URL(filePath: path))
    }
}

private struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(value)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
    }
}

private struct PlistEditorState {
    var program = ""
    var arguments = ""
    var workingDirectory = ""
    var environment = ""
    var standardOutPath = ""
    var standardErrorPath = ""

    init() {}

    init(plist: LaunchPlist) {
        program = plist.program ?? ""
        arguments = plist.programArguments.joined(separator: "\n")
        workingDirectory = plist.workingDirectory ?? ""
        environment = plist.environmentVariables
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        standardOutPath = plist.standardOutPath ?? ""
        standardErrorPath = plist.standardErrorPath ?? ""
    }

    func launchPlist(label: String, preserving plist: LaunchPlist) throws -> LaunchPlist {
        LaunchPlist(
            label: label,
            program: blankNil(program),
            programArguments: lineValues(arguments),
            workingDirectory: blankNil(workingDirectory),
            environmentVariables: try environmentDictionary(environment),
            standardOutPath: blankNil(standardOutPath),
            standardErrorPath: blankNil(standardErrorPath),
            startInterval: plist.startInterval,
            startCalendarIntervals: plist.startCalendarIntervals,
            timeOut: plist.timeOut,
            launchOnlyOnce: plist.launchOnlyOnce,
            runAtLoad: plist.runAtLoad
        )
    }
}

private struct EditorField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .font(.callout)
    }
}

private struct EditorTextArea: View {
    let title: String
    @Binding var text: String
    let height: CGFloat

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow(alignment: .top) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                    .padding(.top, 6)
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: height)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .font(.callout)
    }
}

private struct LogPreview: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 180)
        }
        .padding(10)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.headline)
        content()
    }
    .padding(16)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
}

private func textSection(_ title: String, _ text: String) -> some View {
    section(title) {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func notice(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.headline)
        Text(body)
            .foregroundStyle(.secondary)
    }
    .padding(14)
    .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
}

private func tagPill(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.tertiary.opacity(0.5), in: Capsule())
}

private func ownershipTag(for job: LaunchJobSummary) -> String {
    if job.isAppOwned {
        return "LaunchDeck 관리 항목"
    }
    if isAppleSystem(job) {
        return "Apple 시스템"
    }
    if isPersonalAutomation(job) {
        return "내 자동화"
    }
    return "외부 항목"
}

private func serviceOwner(for job: LaunchJobSummary) -> String {
    let text = serviceText(job: job)

    if job.isAppOwned {
        return "LaunchDeck"
    }
    if isPersonalAutomation(job) {
        return "내 자동화"
    }
    if job.label.hasPrefix("com.apple.") {
        return "Apple"
    }
    if text.contains("logi") || text.contains("logitech") {
        return "Logitech"
    }
    if text.contains("google") || text.contains("keystone") {
        return "Google"
    }
    if text.contains("microsoft") {
        return "Microsoft"
    }
    if text.contains("zoom") {
        return "Zoom"
    }
    if text.contains("cloudflare") || text.contains("cloudflared") {
        return "Cloudflare"
    }
    if text.contains("orbstack") {
        return "OrbStack"
    }
    if text.contains("watchman") || text.contains("facebook") {
        return "Watchman"
    }
    return "알 수 없음"
}

private func matches(_ filter: JobFilter, job: LaunchJobSummary) -> Bool {
    switch filter {
    case .attention:
        needsAttention(job)
    case .mine:
        isPersonalAutomation(job)
    case .external:
        isExternalApp(job)
    case .apple:
        isAppleSystem(job)
    case .all:
        true
    }
}

private func matchesSearch(_ query: String, job: LaunchJobSummary) -> Bool {
    [
        job.label,
        job.plistURL.path,
        job.domainName,
        serviceOwner(for: job),
        job.program ?? "",
        job.programArguments.joined(separator: " "),
    ]
    .joined(separator: " ")
    .lowercased()
    .contains(query)
}

private func needsAttention(_ job: LaunchJobSummary) -> Bool {
    if isAppleSystem(job) {
        return false
    }
    if job.parseError != nil || !FileManager.default.fileExists(atPath: job.plistURL.path) {
        return true
    }
    if missingExecutable(for: job) {
        return true
    }
    if job.label.contains(".proof.") || job.label.contains(".test.") {
        return true
    }
    return isExternalApp(job) && serviceOwner(for: job) == "알 수 없음"
}

private func isPersonalAutomation(_ job: LaunchJobSummary) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
    let userName = NSUserName().lowercased()
    let text = [
        job.label,
        job.program ?? "",
        job.programArguments.joined(separator: " "),
    ]
    .joined(separator: " ")
    .lowercased()

    return job.isAppOwned ||
        (!userName.isEmpty && job.label.lowercased().hasPrefix("com.\(userName).")) ||
        text.contains("\(home)/.agents/") ||
        text.contains("\(home)/.local/bin/") ||
        text.contains("\(home)/bin/") ||
        text.contains("\(home)/scripts/") ||
        text.contains("~/.agents/") ||
        text.contains("~/.local/bin/") ||
        text.contains("~/bin/") ||
        text.contains("~/scripts/") ||
        text.contains("voice-memos")
}

private func isAppleSystem(_ job: LaunchJobSummary) -> Bool {
    job.label.hasPrefix("com.apple.") || job.domainName.hasPrefix("System")
}

private func isExternalApp(_ job: LaunchJobSummary) -> Bool {
    !isAppleSystem(job) && !isPersonalAutomation(job)
}

private func missingExecutable(for job: LaunchJobSummary) -> Bool {
    guard let executable = job.program ?? job.programArguments.first,
          executable.hasPrefix("/")
    else {
        return false
    }

    return !FileManager.default.fileExists(atPath: executable)
}

private func rowIconName(for job: LaunchJobSummary) -> String {
    if needsAttention(job) {
        return "exclamationmark.triangle"
    }
    if isPersonalAutomation(job) {
        return "checkmark.circle"
    }
    return "lock"
}

private func rowIconColor(for job: LaunchJobSummary) -> Color {
    if needsAttention(job) {
        return .orange
    }
    if isPersonalAutomation(job) {
        return .green
    }
    return .secondary
}

private func executablePath(for plist: LaunchPlist?) -> String? {
    plist?.program ?? plist?.programArguments.first
}

private enum LaunchDeckEditorError: Error, CustomStringConvertible {
    case invalidEnvironmentLine(String)

    var description: String {
        switch self {
        case let .invalidEnvironmentLine(line):
            "환경 변수는 KEY=VALUE 형식이어야 합니다: \(line)"
        }
    }
}

private func blankNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func lineValues(_ value: String) -> [String] {
    value
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func environmentDictionary(_ value: String) throws -> [String: String] {
    var result: [String: String] = [:]
    for line in lineValues(value) {
        guard let separator = line.firstIndex(of: "=") else {
            throw LaunchDeckEditorError.invalidEnvironmentLine(line)
        }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            throw LaunchDeckEditorError.invalidEnvironmentLine(line)
        }
        result[key] = value
    }
    return result
}

private func logTail(path: String?) -> String {
    guard let path = path.flatMap(blankNil) else {
        return ""
    }
    guard FileManager.default.fileExists(atPath: path) else {
        return "파일 없음: \(shortPath(path))"
    }

    do {
        let handle = try FileHandle(forReadingFrom: URL(filePath: path))
        defer { try? handle.close() }

        // ponytail: tail only; add live streaming if logs need follow mode.
        let maxBytes: UInt64 = 80 * 1024
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        let data = try handle.readToEnd() ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        if text.isEmpty {
            return "로그가 비어 있습니다."
        }
        return size > maxBytes ? "...\n\(text)" : text
    } catch {
        return "로그를 읽을 수 없습니다: \(error)"
    }
}

private func shortPath(_ value: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if value.hasPrefix(home) {
        return "~" + value.dropFirst(home.count)
    }
    return value
}

private func serviceText(job: LaunchJobSummary, plist: LaunchPlist? = nil) -> String {
    [
        job.label,
        job.plistURL.path,
        job.program ?? "",
        job.programArguments.joined(separator: " "),
        plist?.program ?? "",
        plist?.programArguments.joined(separator: " ") ?? "",
    ]
    .joined(separator: " ")
    .lowercased()
}

private func boolText(_ value: Bool?) -> String {
    guard let value else {
        return "알 수 없음"
    }
    return value ? "예" : "아니오"
}

private func calendarScheduleText(_ schedule: CalendarSchedule) -> String {
    let datePrefix: String
    if let month = schedule.month, let day = schedule.day {
        datePrefix = "매년 \(month)월 \(day)일"
    } else if let day = schedule.day {
        datePrefix = "매월 \(day)일"
    } else if let weekday = schedule.weekday {
        datePrefix = "매주 \(weekdayName(weekday))"
    } else if schedule.hour != nil || schedule.minute != nil {
        datePrefix = "매일"
    } else {
        datePrefix = "예약 시간"
    }

    let time: String
    switch (schedule.hour, schedule.minute) {
    case let (.some(hour), .some(minute)):
        time = String(format: "%02d:%02d", hour, minute)
    case let (.some(hour), .none):
        time = "\(hour)시"
    case let (.none, .some(minute)):
        time = "매시 \(minute)분"
    case (.none, .none):
        time = ""
    }

    return [datePrefix, time]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func weekdayName(_ value: Int) -> String {
    switch value {
    case 0, 7:
        return "일요일"
    case 1:
        return "월요일"
    case 2:
        return "화요일"
    case 3:
        return "수요일"
    case 4:
        return "목요일"
    case 5:
        return "금요일"
    case 6:
        return "토요일"
    default:
        return "요일 \(value)"
    }
}

private func koreanDomain(_ name: String) -> String {
    switch name {
    case "User LaunchAgents":
        "사용자 LaunchAgent"
    case "Local LaunchAgents":
        "공용 LaunchAgent"
    case "Local LaunchDaemons":
        "공용 LaunchDaemon"
    case "System LaunchAgents":
        "시스템 LaunchAgent"
    case "System LaunchDaemons":
        "시스템 LaunchDaemon"
    default:
        name
    }
}
