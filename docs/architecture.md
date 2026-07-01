# Architecture

LaunchDeck has three targets:

```text
LaunchDeckApp  ->  LaunchDeckCore
LaunchDeckCLI  ->  LaunchDeckCore
Tests          ->  LaunchDeckCore
```

The app and CLI share the same plist, task, and `launchctl` code. This keeps the
visual app honest: the proof script can exercise the same core behavior without
depending on screenshots.

## Core concepts

### Inventory

`LaunchInventoryService` scans the standard launchd directories:

- `~/Library/LaunchAgents`
- `/Library/LaunchAgents`
- `/Library/LaunchDaemons`
- `/System/Library/LaunchAgents`
- `/System/Library/LaunchDaemons`

Each plist becomes a `LaunchJobSummary`. The summary stores the label, source
path, domain name, write permission boundary, command fields, log paths, and any
parse error. The unique identity is the plist path, not only the launchd label,
because the same label can appear in more than one domain.

### Plist model

`LaunchPlist` reads and writes the subset LaunchDeck needs:

- `Label`
- `Program`
- `ProgramArguments`
- `WorkingDirectory`
- `EnvironmentVariables`
- `StandardOutPath`
- `StandardErrorPath`
- `StartInterval`
- `StartCalendarInterval`
- `TimeOut`
- `LaunchOnlyOnce`
- `RunAtLoad`

`LaunchPlist.propertyList(appOwned:)` validates labels before rendering XML. For
app-owned writes, labels must start with `io.github.launchdeck.`.

### launchctl wrapper

`Launchctl` uses the current user GUI domain, `gui/<uid>`, for operations:

- `bootstrap gui/<uid> <plist>`
- `bootout gui/<uid> <plist>`
- `enable gui/<uid>/<label>`
- `disable gui/<uid>/<label>`
- `kickstart -kp gui/<uid>/<label>`
- `list <label>`
- `print gui/<uid>/<label>`
- `print-disabled gui/<uid>`

Status is represented by `LaunchctlStatusSnapshot`. It intentionally separates:

- plist file exists
- service is loaded
- service has a running PID
- service has a last exit status
- service is disabled
- raw diagnostic output

The code does not treat `launchctl print` as a stable machine API. It is exposed
as raw diagnostic text for people.

### Managed tasks

`ManagedTask` is the app-owned task format. It supports:

- one-shot schedules
- calendar schedules
- interval schedules
- command arguments
- working directory
- environment variables
- stdout and stderr paths
- timeout
- after-run policy
- run history

`ManagedTaskTemplate` creates labels under `io.github.launchdeck.task.*` and log
paths under `~/Library/Logs/LaunchDeck/`.

One-shot tasks cannot use `afterRunPolicy.keep`. A launchd calendar entry for a
specific day and month can repeat yearly, so LaunchDeck requires one-shot tasks
to disable or clean up after running.

## App flow

```text
User selects job
  -> app reads plist
  -> app refreshes launchctl status
  -> user runs/loads/unloads/enables/disables
  -> app refreshes status again
  -> user opens logs only when needed
```

The detail view keeps operations at the top. Logs are lazy-loaded because launchd
jobs can write large files, and selection should stay fast.

## CLI flow

The CLI uses `LaunchDeckService`, which combines:

- `ManagedTaskStore`
- `LaunchAgentPlistStore`
- `PlistLinter`
- `Launchctl`

When loading an app-owned task, the service renders the plist, runs
`plutil -lint`, then calls `launchctl bootstrap`. Lifecycle actions append JSONL
history under `~/Library/Application Support/LaunchDeck/history/`.

## Trade-offs

- The app edits common plist fields, not every launchd plist key.
- The UI can operate personal user LaunchAgents, but system and local daemon
  paths stay read-only.
- Log preview reads the tail of a file, not a live stream.
- Release signing and installer packaging are outside this repository for now.
