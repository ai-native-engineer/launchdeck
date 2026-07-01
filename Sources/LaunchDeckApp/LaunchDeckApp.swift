import AppKit
import LaunchDeckCore
import SwiftUI

@main
struct LaunchDeckApp: App {
    var body: some Scene {
        WindowGroup("LaunchDeck") {
            LaunchDeckContentView()
        }
        .defaultSize(width: 1180, height: 720)
    }
}

private struct LaunchDeckContentView: View {
    @State private var jobs = LaunchInventoryService().inventory()
    @State private var selection: String?

    private var selectedJob: LaunchJobSummary? {
        jobs.first { $0.id == selection }
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

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(jobs) { job in
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
                    Text(koreanDomain(job.domainName))
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
