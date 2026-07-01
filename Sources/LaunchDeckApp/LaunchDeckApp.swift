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
        window.center()
        window.title = "LaunchDeck"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LaunchDeckContentView())
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

private struct LaunchDeckContentView: View {
    @State private var jobs = LaunchInventoryService().inventory()
    @State private var selection: String?
    @State private var searchText = ""

    private var selectedJob: LaunchJobSummary? {
        jobs.first { $0.id == selection }
    }

    private var visibleJobs: [LaunchJobSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return jobs
        }

        return jobs.filter { job in
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

                Divider()

                ScrollView {
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
    }
}

private struct JobRow: View {
    let job: LaunchJobSummary
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: job.isWritable && job.isAppOwned ? "checkmark.circle" : "lock")
                    .foregroundStyle(job.isWritable && job.isAppOwned ? .green : .secondary)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !canManage {
                    notice("읽기 전용", "LaunchDeck이 만든 사용자 LaunchAgent만 불러오기, 내리기, 실행, 활성화, 비활성화를 허용합니다.")
                }

                insightSection
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
        }
        .onChange(of: job.id) { _, _ in
            loadDetails()
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
                tagPill(job.isAppOwned ? "LaunchDeck 관리 항목" : "외부 항목")
                tagPill(canManage ? "쓰기 가능" : "읽기 전용")
            }
        }
    }

    private var insightSection: some View {
        section("판단") {
            InfoGrid(rows: [
                ("소속 추정", serviceOwner(for: job)),
                ("역할 추정", servicePurpose(for: job, plist: plist)),
                ("정리 판단", serviceRecommendation(for: job, plist: plist, status: status)),
                ("주의 신호", cleanupSignals(for: job, plist: plist, status: status).joined(separator: "\n")),
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
            return plist.startCalendarIntervals.map(describe).joined(separator: "\n")
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

private func serviceOwner(for job: LaunchJobSummary) -> String {
    let text = serviceText(job: job)

    if job.isAppOwned {
        return "LaunchDeck"
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

private func servicePurpose(for job: LaunchJobSummary, plist: LaunchPlist?) -> String {
    let text = serviceText(job: job, plist: plist)

    if job.isAppOwned {
        return "사용자가 만든 LaunchDeck 자동화입니다."
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

private func serviceRecommendation(
    for job: LaunchJobSummary,
    plist: LaunchPlist?,
    status: LaunchctlStatusSnapshot?
) -> String {
    if job.parseError != nil {
        return "plist를 읽지 못했습니다. 삭제보다 파일 형식과 소유 앱을 먼저 확인하세요."
    }
    if !FileManager.default.fileExists(atPath: job.plistURL.path) {
        return "plist 파일이 없습니다. 정리 후보입니다."
    }
    if let executable = executablePath(for: plist), executable.hasPrefix("/"),
       !FileManager.default.fileExists(atPath: executable) {
        return "실행 파일이 없습니다. 앱 삭제 후 남은 항목일 가능성이 있어 정리 후보입니다."
    }
    if job.domainName.hasPrefix("System") || job.label.hasPrefix("com.apple.") {
        return "시스템 항목입니다. 문제를 특정하지 못했다면 끄지 않는 편이 맞습니다."
    }
    if job.isAppOwned {
        return "내 자동화입니다. 더 이상 쓰지 않으면 LaunchDeck에서 정리해도 됩니다."
    }
    if let lastExit = status?.lastExitStatus, lastExit != 0 {
        return "최근 종료 코드가 0이 아닙니다. 로그를 먼저 확인하세요."
    }
    if serviceOwner(for: job) == "알 수 없음" {
        return "출처가 불명확합니다. 실행 파일 경로와 로그를 확인한 뒤 판단하세요."
    }
    return "해당 앱을 쓰고 있다면 유지, 안 쓰면 비활성화 후보입니다."
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

private func describe(_ schedule: CalendarSchedule) -> String {
    [
        schedule.month.map { "\($0)월" },
        schedule.day.map { "\($0)일" },
        schedule.weekday.map { "요일 \($0)" },
        schedule.hour.map { "\($0)시" },
        schedule.minute.map { "\($0)분" },
    ]
    .compactMap { $0 }
    .joined(separator: " ")
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
