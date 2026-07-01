# CLI Reference

The `launchdeck` executable is the command-line interface for LaunchDeck.

Build it first:

```bash
swift build --product launchdeck
```

Run commands through the debug executable:

```bash
.build/debug/launchdeck version
```

## Commands

### domains

Prints the launchd domains LaunchDeck scans and whether each domain is writable.

```bash
.build/debug/launchdeck domains
```

Output columns:

```text
name    mode    path
```

### inventory

Lists discovered launchd jobs.

```bash
.build/debug/launchdeck inventory
```

Output columns:

```text
label   domain  mode    plist-path
```

### inspect

Reads launchctl status for an arbitrary label and plist path.

```bash
.build/debug/launchdeck inspect <label> <plist-path>
```

The output separates plist existence, loaded state, PID, last exit status,
disabled state, and raw command exit codes.

### inspect-raw

Prints raw diagnostic output from the same launchctl status calls used by
`inspect`.

```bash
.build/debug/launchdeck inspect-raw <label> <plist-path>
```

Use this when the structured status does not explain what launchd is doing.

### create-interval

Creates app-owned task metadata for a repeating interval.

```bash
.build/debug/launchdeck create-interval <id> <seconds> -- <program> [args...]
```

Example:

```bash
.build/debug/launchdeck create-interval heartbeat 3600 -- /bin/echo alive
```

### create-calendar

Creates app-owned task metadata for a calendar schedule.

```bash
.build/debug/launchdeck create-calendar <id> <minute> <hour> -- <program> [args...]
```

Example:

```bash
.build/debug/launchdeck create-calendar cleanup 0 3 -- /bin/sh "$HOME/.local/bin/cleanup.sh"
```

### create-one-shot

Creates app-owned task metadata for a one-shot schedule.

```bash
.build/debug/launchdeck create-one-shot <id> <unix-seconds> -- <program> [args...]
```

One-shot tasks are rendered with `LaunchOnlyOnce` and must disable or clean up
after running.

### tasks

Lists app-owned task metadata saved under LaunchDeck's application support
directory.

```bash
.build/debug/launchdeck tasks
```

Output columns:

```text
id  title   label
```

### render-plist

Renders a managed task JSON file to a LaunchAgent plist.

```bash
.build/debug/launchdeck render-plist <task-json> <plist-output>
```

The rendered plist is validated by the same model used by the app and tests.

### load

Installs and bootstraps an app-owned task.

```bash
.build/debug/launchdeck load <id>
```

The service writes the plist to `~/Library/LaunchAgents/`, runs `plutil -lint`,
then calls `launchctl bootstrap gui/<uid> <plist>`.

### unload

Boots out an app-owned task.

```bash
.build/debug/launchdeck unload <id>
```

### run

Runs an app-owned task now using `launchctl kickstart -kp`.

```bash
.build/debug/launchdeck run <id>
```

The task must already be loadable as a user LaunchAgent.

### enable

Enables an app-owned task.

```bash
.build/debug/launchdeck enable <id>
```

### disable

Disables an app-owned task.

```bash
.build/debug/launchdeck disable <id>
```

### status

Prints structured status for an app-owned task.

```bash
.build/debug/launchdeck status <id>
```

Fields:

```text
label
service_target
plist_exists
loaded
running_pid
last_exit_status
disabled
raw_list_exit
raw_print_exit
raw_disabled_exit
```

### diagnose

Prints raw diagnostic output for an app-owned task.

```bash
.build/debug/launchdeck diagnose <id>
```

### history

Prints lifecycle history for an app-owned task.

```bash
.build/debug/launchdeck history <id>
```

Output columns:

```text
task-id action  exit-code   occurred-at
```

### log

Prints a saved app-owned task log.

```bash
.build/debug/launchdeck log <id> <stdout|stderr>
```

## Storage

App-owned CLI tasks use these paths:

```text
~/Library/Application Support/LaunchDeck/tasks/
~/Library/Application Support/LaunchDeck/history/
~/Library/LaunchAgents/io.github.launchdeck.task.<id>.plist
~/Library/Logs/LaunchDeck/<id>.stdout.log
~/Library/Logs/LaunchDeck/<id>.stderr.log
```

## Exit behavior

The CLI exits with status `1` when a command throws an error. Lifecycle commands
also fail when the underlying `launchctl` or `plutil` command exits non-zero.
