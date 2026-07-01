# LaunchDeck

LaunchDeck is a macOS app and CLI for inspecting and operating `launchd` jobs.

It is built for the local automation workflow: find a LaunchAgent, check whether
`launchd` has loaded it, run it now, inspect logs when needed, edit the command
paths for user automations, and try again.

## What it does

- Inventories LaunchAgents and LaunchDaemons from the standard macOS locations.
- Separates plist existence from loaded state, running PID, disabled state, and
  last exit status.
- Lets you run, load, unload, enable, and disable editable user automations.
- Edits common plist fields for personal LaunchAgents, with `plutil -lint`
  validation before saving.
- Opens stdout and stderr logs on demand instead of reading large logs during
  selection.
- Provides a `launchdeck` CLI that shares the same core logic as the app.

LaunchDeck is not a privileged system daemon manager. System and local daemon
paths are read-only in this project.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Apple platform tools available from PATH: `launchctl` and `plutil`

## Run the app

```bash
./scripts/run-app.sh
```

The script builds `LaunchDeckApp`, creates a local `.build/LaunchDeck.app`
bundle, validates its `Info.plist`, and opens the app.

## Build and test

```bash
swift build
swift test
./scripts/proof.sh
```

`scripts/proof.sh` runs the build, tests, placeholder scan, fixture plist
rendering, and `plutil -lint` checks. The live launchd proof is opt-in because it
creates a temporary user LaunchAgent:

```bash
RUN_LIVE_LAUNCHD=1 ./scripts/proof.sh
```

The live proof only uses labels matching `io.github.launchdeck.proof.*` and
cleans up its generated plist, script, task metadata, and marker file.

## CLI quick start

```bash
swift build --product launchdeck
.build/debug/launchdeck inventory
.build/debug/launchdeck inspect com.example.agent ~/Library/LaunchAgents/com.example.agent.plist
```

Create and run an app-owned interval task:

```bash
.build/debug/launchdeck create-interval hello 300 -- /bin/echo hello
.build/debug/launchdeck load hello
.build/debug/launchdeck run hello
.build/debug/launchdeck status hello
.build/debug/launchdeck log hello stdout
```

App-owned tasks use labels under `io.github.launchdeck.task.*`, metadata under
`~/Library/Application Support/LaunchDeck/`, LaunchAgent plists under
`~/Library/LaunchAgents/`, and logs under `~/Library/Logs/LaunchDeck/`.

## Documentation

- [Architecture](docs/architecture.md)
- [CLI reference](docs/cli.md)
- [Safety model](docs/safety.md)

## Repository layout

```text
Sources/LaunchDeckApp/       SwiftUI macOS app
Sources/LaunchDeckCLI/       launchdeck command-line interface
Sources/LaunchDeckCore/      plist, launchctl, task, and inventory logic
Tests/LaunchDeckCoreTests/   core behavior and launchctl wrapper tests
Fixtures/managed-tasks/      sample managed task JSON fixtures
scripts/                    local app runner and proof script
docs/                       project documentation
```

## Current boundaries

LaunchDeck currently focuses on user LaunchAgents and app-owned task generation.
It does not install privileged helpers, edit `/System/Library/*`, edit
`/Library/LaunchDaemons`, notarize release builds, or package a signed installer.

Before making the repository public for reuse, choose a license and add release
screenshots or signed artifacts if those are part of the distribution plan.
