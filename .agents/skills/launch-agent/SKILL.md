---
argument-hint: "[task]"
name: launch-agent
description: "macOS LaunchAgent plist 작성, launchctl bootstrap/bootout/kickstart 상태 진단, 로그 경로, 스케줄, WatchPaths/QueueDirectories, user GUI domain 문제를 공식 launchd manpage 기준으로 처리. Use when user asks LaunchAgent 만들어줘, launchd plist 수정, launchctl 에러, 자동 실행, 로그인 시 실행, 주기 실행, macOS 백그라운드 작업, watcher 안 돎, 로그 안 찍힘. Do NOT use for non-macOS schedulers, systemd, cron-only jobs, privileged LaunchDaemon design, or generic app UI work."
---

# Launch Agent

macOS 사용자 LaunchAgent를 만들고 고칠 때 쓰는 스킬이다. 목표는 plist를 예쁘게 쓰는 것이 아니라, `launchd`가 실제로 로드하고 실행하고 로그를 남기는 상태까지 확인하는 것이다.

## Workflow

1. 먼저 범위를 정한다.
   - 사용자 단위 작업이면 `~/Library/LaunchAgents/<label>.plist`와 `gui/$(id -u)`를 기본으로 둔다.
   - root/system daemon, `/Library/LaunchDaemons`, privileged helper가 필요하면 별도 설계로 분리한다.

2. `references/launch-agent-playbook.md`를 읽고 작업한다.
   - 새 plist 작성, 기존 plist 수정, 상태 진단, 로그 진단 모두 이 reference를 따른다.

3. plist 저장 전후로 검증한다.
   - `plutil -lint <plist>`
   - `launchctl bootout gui/$(id -u) <plist> 2>/dev/null || true`
   - `launchctl bootstrap gui/$(id -u) <plist>`
   - `launchctl kickstart -kp gui/$(id -u)/<label>`
   - `launchctl print gui/$(id -u)/<label>`

4. 상태를 파일 존재로 판단하지 않는다.
   - plist가 있는 것과 launchd에 loaded 된 것은 다르다.
   - loaded/running/disabled/last exit/log output을 따로 확인한다.

## Defaults

- `ProgramArguments`를 기본으로 쓴다.
- 실행 파일은 절대 경로로 둔다.
- `PATH`가 필요하면 `EnvironmentVariables`에 명시한다.
- stdout/stderr는 로컬 쓰기 가능 경로에 둔다.
- GUI 앱/사용자 세션 기능이 필요하면 `LimitLoadToSessionType`은 보통 `Aqua`다.
- 반복 실행은 `StartInterval`, 달력 기반 실행은 `StartCalendarInterval`을 쓴다.

## Safety

- `/System/Library/*`는 읽기 전용으로만 본다.
- `/Library/LaunchDaemons`나 root 권한 작업은 사용자 요청이 명확할 때만 다룬다.
- `launchctl load/unload`보다 `bootstrap/bootout/enable/disable/kickstart`를 우선한다.
- `launchctl print` 출력 구조를 자동화 API로 파싱하지 않는다. 사람 진단용으로만 쓴다.

## Completion

완료 보고에는 아래를 포함한다.

- plist 경로와 label
- `plutil -lint` 결과
- bootstrap/bootout/kickstart 결과
- stdout/stderr 경로
- 남은 제약: 권한, GUI 세션, FDA, sleep 중 missed interval 같은 조건
