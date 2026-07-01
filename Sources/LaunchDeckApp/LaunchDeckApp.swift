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
                    JobDetailView(job: job)
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

    @State private var plist: LaunchPlist?
    @State private var status: LaunchctlStatusSnapshot?
    @State private var errorText = ""
    @State private var rawDiagnostic = ""

    private var canManage: Bool {
        job.isWritable && job.isAppOwned
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("detail-top")

                VStack(alignment: .leading, spacing: 18) {
                    header
                    decisionHero

                    if !canManage {
                        notice("읽기 전용", "LaunchDeck이 만든 사용자 LaunchAgent만 불러오기, 내리기, 실행, 활성화, 비활성화를 허용합니다.")
                    }

                    contextSection
                    statusSection
                    commandSection
                    scheduleSection
                    logSection
                    actionSection

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
                tagPill(canManage ? "쓰기 가능" : "읽기 전용")
            }
        }
    }

    private var decisionHero: some View {
        DecisionHero(summary: decisionSummary(for: job, plist: plist, status: status))
    }

    private var contextSection: some View {
        section("질문별 해석") {
            InfoGrid(rows: [
                ("이게 뭐냐", servicePurpose(for: job, plist: plist)),
                ("왜 켜져 있나", serviceNeed(for: job, plist: plist)),
                ("끄면", serviceImpact(for: job, plist: plist)),
                ("확인할 것", serviceCheckItems(for: job, plist: plist, status: status)),
            ])
        }
    }

    private var statusSection: some View {
        section("상태") {
            InfoGrid(rows: [
                ("plist 파일", plistExistsText),
                ("launchd 로드", loadedText),
                ("실행 PID", runningPIDText),
                ("비활성화", disabledText),
                ("마지막 종료 코드", lastExitStatusText),
            ])
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
                Button("표준 출력 열기") { openPath(plist?.standardOutPath) }
                    .disabled(plist?.standardOutPath == nil)
                Button("표준 에러 열기") { openPath(plist?.standardErrorPath) }
                    .disabled(plist?.standardErrorPath == nil)
            }
        }
    }

    private var actionSection: some View {
        section("작업") {
            HStack {
                Button("불러오기") { run("불러오기") { try Launchctl().bootstrap(plistURL: job.plistURL) } }
                Button("내리기") { run("내리기") { try Launchctl().bootout(plistURL: job.plistURL) } }
                Button("활성화") { run("활성화") { try Launchctl().enable(label: job.label) } }
                Button("비활성화") { run("비활성화") { try Launchctl().disable(label: job.label) } }
                Button("지금 실행") { run("지금 실행") { try Launchctl().kickstart(label: job.label) } }
            }
            .disabled(!canManage)

            HStack {
                Button("상태 새로고침") { refreshStatus() }
                Button("원본 진단 보기") { showRawDiagnostic() }
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
            plist = try LaunchPlist.read(from: job.plistURL)
        } catch {
            plist = nil
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

    private func run(_ name: String, action: () throws -> CommandResult) {
        do {
            let result = try action()
            errorText = "\(name): 종료 코드 \(result.exitCode)"
            refreshStatus()
        } catch {
            errorText = "\(name): \(error)"
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

private struct DecisionSummary {
    let badge: String
    let headline: String
    let explanation: String
    let nextAction: String
    let impact: String
    let evidence: String
    let systemImage: String
    let color: Color
}

private struct DecisionHero: View {
    let summary: DecisionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(summary.badge, systemImage: summary.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(summary.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(summary.color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .top, spacing: 18) {
                DecisionFact(title: "다음 행동", value: summary.nextAction)
                DecisionFact(title: "끄면", value: summary.impact)
                DecisionFact(title: "근거", value: summary.evidence)
            }
        }
        .padding(18)
        .background(summary.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(summary.color.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct DecisionFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let text = [
        job.label,
        job.program ?? "",
        job.programArguments.joined(separator: " "),
    ]
    .joined(separator: " ")
    .lowercased()

    return job.isAppOwned ||
        job.label.hasPrefix("com.seungwonan.") ||
        text.contains("/.agents/") ||
        text.contains("/.local/bin/") ||
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

private func decisionSummary(
    for job: LaunchJobSummary,
    plist: LaunchPlist?,
    status: LaunchctlStatusSnapshot?
) -> DecisionSummary {
    let evidence = decisionEvidence(for: job, plist: plist, status: status)
    let impact = serviceImpact(for: job, plist: plist)

    if job.parseError != nil {
        return DecisionSummary(
            badge: "확인 필요",
            headline: "\(friendlyServiceName(for: job)) plist를 읽지 못했습니다.",
            explanation: "LaunchDeck이 이 항목의 실행 명령과 스케줄을 해석하지 못했습니다. 파일이 깨졌거나 launchd plist 형식이 아닐 수 있습니다.",
            nextAction: "삭제보다 파일 형식과 소유 앱을 먼저 확인하세요.",
            impact: "출처를 확인하지 않고 끄면 앱 기능이 갑자기 멈출 수 있습니다.",
            evidence: evidence,
            systemImage: "exclamationmark.triangle",
            color: .orange
        )
    }

    if !FileManager.default.fileExists(atPath: job.plistURL.path) {
        return DecisionSummary(
            badge: "정리 후보",
            headline: "\(friendlyServiceName(for: job)) plist 파일이 없습니다.",
            explanation: "목록에는 남아 있지만 실제 plist 파일을 찾을 수 없습니다. 예전 앱이나 자동화가 남긴 흔적일 가능성이 큽니다.",
            nextAction: "경로를 확인한 뒤 남은 항목이면 정리하세요.",
            impact: "대부분 영향이 없지만, 원본 파일이 다른 위치에 있는지는 확인이 필요합니다.",
            evidence: evidence,
            systemImage: "trash",
            color: .red
        )
    }

    if isAppleSystem(job) {
        return DecisionSummary(
            badge: "시스템 항목",
            headline: "macOS가 관리하는 백그라운드 작업입니다.",
            explanation: "사용자 자동화나 외부 앱 정리 대상이 아니라 시스템 기능의 일부로 보는 편이 맞습니다.",
            nextAction: "문제를 특정하지 못했다면 유지하세요.",
            impact: impact,
            evidence: evidence,
            systemImage: "lock",
            color: .secondary
        )
    }

    if let executable = executablePath(for: plist), executable.hasPrefix("/"),
       !FileManager.default.fileExists(atPath: executable) {
        return DecisionSummary(
            badge: "정리 후보",
            headline: "\(friendlyServiceName(for: job)) 실행 파일이 없습니다.",
            explanation: "plist는 남아 있지만 실제 실행할 파일이 사라졌습니다. 앱 삭제 후 남은 LaunchAgent일 가능성이 큽니다.",
            nextAction: "원본 앱을 지웠다면 비활성화하거나 정리하세요.",
            impact: "이미 실행 파일이 없어서 정상 동작하지 않을 가능성이 큽니다.",
            evidence: evidence,
            systemImage: "trash",
            color: .red
        )
    }

    if isPersonalAutomation(job) {
        return DecisionSummary(
            badge: "내 자동화",
            headline: "\(triggerSummary(for: plist))에 \(taskName(for: job, plist: plist)) 실행",
            explanation: servicePurpose(for: job, plist: plist),
            nextAction: "지금도 쓰는 자동화면 유지하고, 아니라면 비활성화 후보로 보세요.",
            impact: impact,
            evidence: evidence,
            systemImage: "checkmark.circle",
            color: .green
        )
    }

    if serviceOwner(for: job) == "알 수 없음" {
        return DecisionSummary(
            badge: "확인 필요",
            headline: "\(friendlyServiceName(for: job)) 출처가 명확하지 않습니다.",
            explanation: "라벨과 실행 경로만으로는 어떤 앱이 등록했는지 확실하지 않습니다.",
            nextAction: "실행 파일 경로와 로그를 먼저 확인하세요.",
            impact: impact,
            evidence: evidence,
            systemImage: "questionmark.circle",
            color: .orange
        )
    }

    return DecisionSummary(
        badge: serviceOwner(for: job),
        headline: "\(serviceOwner(for: job)) 앱의 백그라운드 작업입니다.",
        explanation: servicePurpose(for: job, plist: plist),
        nextAction: "해당 앱을 쓰고 있으면 유지하고, 안 쓰면 비활성화 후보입니다.",
        impact: impact,
        evidence: evidence,
        systemImage: "app.badge",
        color: .blue
    )
}

private func servicePurpose(for job: LaunchJobSummary, plist: LaunchPlist?) -> String {
    let text = serviceText(job: job, plist: plist)

    if job.isAppOwned {
        return "사용자가 만든 LaunchDeck 자동화입니다."
    }
    if text.contains("cleanup-deps") {
        return "cleanup-deps.sh를 정해진 시간에 실행하는 로컬 정리 자동화입니다."
    }
    if text.contains("mac-heartbeat") {
        return "맥 상태를 주기적으로 기록하거나 살아있는지 확인하는 개인 자동화입니다."
    }
    if text.contains("voice-memos") {
        return "음성 메모 파일을 감시하거나 후처리하는 개인 자동화입니다."
    }
    if job.domainName.hasPrefix("System") || job.label.hasPrefix("com.apple.") {
        return "macOS 시스템 기능 또는 Apple 기본 백그라운드 작업입니다."
    }
    if text.contains("update") || text.contains("updater") || text.contains("keystone") {
        return "앱 업데이트 확인 또는 설치 보조 작업입니다."
    }
    if text.contains("logi") || text.contains("logitech") {
        return "Logitech 장치 설정, 버튼 매핑, 옵션 관리용 보조 작업으로 보입니다."
    }
    if text.contains("cloudflared") {
        return "Cloudflare 터널 또는 네트워크 연결 유지 작업으로 보입니다."
    }
    if text.contains("watchman") {
        return "파일 변경 감시용 개발 도구 작업으로 보입니다."
    }
    if plist?.startInterval != nil || plist?.startCalendarIntervals.isEmpty == false {
        return "정해진 주기로 실행되는 예약 작업입니다."
    }
    if plist?.runAtLoad == true {
        return "로그인 또는 로드 시 자동 실행되는 앱 보조 작업입니다."
    }
    return "앱이 필요할 때 호출하는 보조 프로세스일 가능성이 큽니다."
}

private func serviceNeed(for job: LaunchJobSummary, plist: LaunchPlist?) -> String {
    let text = serviceText(job: job, plist: plist)

    if text.contains("cleanup-deps") {
        return "정리 스크립트를 잊지 않고 자동으로 돌리기 위해 필요합니다."
    }
    if text.contains("mac-heartbeat") {
        return "상태 기록이나 자동화 감시 흐름을 계속 유지하려고 필요합니다."
    }
    if text.contains("voice-memos") {
        return "새 음성 메모를 놓치지 않고 처리하려고 필요합니다."
    }
    if text.contains("keystone") || text.contains("googleupdater") {
        return "Google 앱 업데이트를 백그라운드에서 처리하려고 필요합니다."
    }
    if text.contains("cloudflared") {
        return "Cloudflare 터널이나 네트워크 연결을 계속 유지하려고 필요합니다."
    }
    if text.contains("watchman") {
        return "개발 도구가 파일 변경을 빠르게 감지하려고 필요합니다."
    }
    if serviceOwner(for: job) == "Logitech" {
        return "Logitech 장치 설정과 버튼 매핑을 유지하려고 필요합니다."
    }
    if isAppleSystem(job) {
        return "macOS 기능 일부라 사용자가 직접 관리할 항목은 아닙니다."
    }
    if isPersonalAutomation(job) {
        return "직접 만든 로컬 자동화 흐름을 유지하려고 필요합니다."
    }
    return "해당 앱이 로그인 후 보조 기능을 바로 쓰기 위해 등록한 항목입니다."
}

private func serviceImpact(for job: LaunchJobSummary, plist: LaunchPlist?) -> String {
    let text = serviceText(job: job, plist: plist)

    if text.contains("cleanup-deps") {
        return "정리 스크립트가 자동으로 돌지 않습니다."
    }
    if text.contains("mac-heartbeat") {
        return "맥 상태 기록이나 감시 흐름이 멈춥니다."
    }
    if text.contains("voice-memos") {
        return "새 음성 메모 감시나 후처리가 자동으로 돌지 않습니다."
    }
    if text.contains("keystone") || text.contains("googleupdater") {
        return "Google 앱 업데이트가 늦어질 수 있습니다."
    }
    if text.contains("cloudflared") {
        return "Cloudflare 터널이나 네트워크 연결이 끊길 수 있습니다."
    }
    if text.contains("watchman") {
        return "개발 도구의 파일 변경 감지가 느려지거나 실패할 수 있습니다."
    }
    if serviceOwner(for: job) == "Logitech" {
        return "Logitech 장치 설정이나 버튼 매핑이 적용되지 않을 수 있습니다."
    }
    if isAppleSystem(job) {
        return "macOS 기능 일부가 동작하지 않을 수 있습니다."
    }
    if isPersonalAutomation(job) {
        return "직접 만든 자동화가 더 이상 자동 실행되지 않습니다."
    }
    return "소유 앱의 로그인 후 보조 기능이 동작하지 않을 수 있습니다."
}

private func serviceCheckItems(
    for job: LaunchJobSummary,
    plist: LaunchPlist?,
    status: LaunchctlStatusSnapshot?
) -> String {
    let signals = cleanupSignals(for: job, plist: plist, status: status)
    if signals != ["특이사항 없음"] {
        return signals.joined(separator: "\n")
    }
    if isPersonalAutomation(job) {
        return "스크립트 경로가 아직 맞는지, 로그가 최근에도 쌓이는지 확인하세요."
    }
    if isAppleSystem(job) {
        return "보통 확인할 필요 없습니다. 문제가 있을 때만 로그를 봅니다."
    }
    return "이 앱을 지금도 쓰는지, 실행 파일 경로가 설치된 앱과 맞는지 확인하세요."
}

private func cleanupSignals(
    for job: LaunchJobSummary,
    plist: LaunchPlist?,
    status: LaunchctlStatusSnapshot?
) -> [String] {
    var signals: [String] = []

    if job.parseError != nil {
        signals.append("plist 파싱 실패")
    }
    if !FileManager.default.fileExists(atPath: job.plistURL.path) {
        signals.append("plist 파일 없음")
    }
    if let executable = executablePath(for: plist), executable.hasPrefix("/"),
       !FileManager.default.fileExists(atPath: executable) {
        signals.append("실행 파일 없음")
    }
    if job.label.contains(".proof.") || job.label.contains(".test.") {
        signals.append("테스트/검증 항목처럼 보임")
    }
    if let lastExit = status?.lastExitStatus, lastExit != 0 {
        signals.append("마지막 종료 코드 \(lastExit)")
    }
    if signals.isEmpty {
        signals.append("특이사항 없음")
    }

    return signals
}

private func executablePath(for plist: LaunchPlist?) -> String? {
    plist?.program ?? plist?.programArguments.first
}

private func decisionEvidence(
    for job: LaunchJobSummary,
    plist: LaunchPlist?,
    status: LaunchctlStatusSnapshot?
) -> String {
    var values = [
        "\(koreanDomain(job.domainName))",
        shortPath(job.plistURL.path),
    ]

    if plist != nil {
        values.append(commandSummary(for: plist))
        values.append(triggerSummary(for: plist))
    }

    if let status {
        if let pid = status.runningPID {
            values.append("현재 PID \(pid)")
        } else {
            values.append(status.loaded ? "로드됨" : "로드 안 됨")
        }
        if let lastExit = status.lastExitStatus {
            values.append("마지막 종료 코드 \(lastExit)")
        }
    } else {
        values.append("실행 상태는 새로고침 전")
    }

    return values.joined(separator: "\n")
}

private func commandSummary(for plist: LaunchPlist?) -> String {
    guard let plist else {
        return "명령을 읽을 수 없음"
    }

    let values: [String]
    if !plist.programArguments.isEmpty {
        values = plist.programArguments
    } else if let program = plist.program {
        values = [program]
    } else {
        values = []
    }

    if values.isEmpty {
        return "명령 없음"
    }

    return values.map(shortPath).joined(separator: " ")
}

private func triggerSummary(for plist: LaunchPlist?) -> String {
    guard let plist else {
        return "스케줄 확인 전"
    }

    if let interval = plist.startInterval {
        return "\(interval)초마다"
    }
    if plist.startCalendarIntervals.count == 1, let schedule = plist.startCalendarIntervals.first {
        return calendarScheduleText(schedule)
    }
    if !plist.startCalendarIntervals.isEmpty {
        return "\(plist.startCalendarIntervals.count)개 예약 시간"
    }
    if plist.runAtLoad {
        return "로그인 또는 로드 시"
    }
    return "수동 요청 시"
}

private func taskName(for job: LaunchJobSummary, plist: LaunchPlist?) -> String {
    let text = serviceText(job: job, plist: plist)

    if text.contains("cleanup-deps") {
        return "cleanup-deps.sh"
    }
    if text.contains("mac-heartbeat") {
        return "mac-heartbeat"
    }
    if text.contains("voice-memos") {
        return "voice-memos watcher"
    }

    let arguments = plist?.programArguments ?? job.programArguments
    if let script = arguments.dropFirst().first(where: { $0.hasPrefix("/") || $0.contains(".sh") }) {
        return URL(filePath: script).lastPathComponent
    }
    if let executable = executablePath(for: plist) ?? job.program ?? job.programArguments.first {
        return URL(filePath: executable).lastPathComponent
    }
    return friendlyServiceName(for: job)
}

private func friendlyServiceName(for job: LaunchJobSummary) -> String {
    let text = serviceText(job: job)

    if text.contains("cleanup-deps") {
        return "cleanup-deps"
    }
    if text.contains("mac-heartbeat") {
        return "mac-heartbeat"
    }
    if text.contains("voice-memos") {
        return "voice-memos watcher"
    }
    if text.contains("cloudflared") {
        return "cloudflared"
    }
    if text.contains("watchman") {
        return "watchman"
    }
    if text.contains("keystone") {
        return "Google Keystone"
    }

    let parts = job.label.split(separator: ".").map(String.init)
    if let last = parts.last, !last.isEmpty {
        return last
    }
    return job.label
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
