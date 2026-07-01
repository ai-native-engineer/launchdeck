# LaunchAgent Playbook

사용자 LaunchAgent를 작성, 수정, 진단할 때 따르는 절차다.

## 1. Choose The Right Job Type

Use `~/Library/LaunchAgents` when the job runs for one user.

Use `/Library/LaunchAgents` when an administrator installs a per-user agent for all users.

Use `/Library/LaunchDaemons` only for root/system-wide daemons. Do not turn a user automation into a daemon just to make it "stronger"; daemons do not inherit a user's GUI/bootstrap/security context.

For normal user automations, prefer:

```text
plist: ~/Library/LaunchAgents/<label>.plist
domain: gui/$(id -u)
service target: gui/$(id -u)/<label>
```

## 2. Minimal Plist Template

Use `ProgramArguments` unless there is a specific reason to split `Program` and arguments.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.my-agent</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/example/.local/bin/my-script.sh</string>
  </array>

  <key>WorkingDirectory</key>
  <string>/Users/example</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>StandardOutPath</key>
  <string>/Users/example/Library/Logs/my-agent.out.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/example/Library/Logs/my-agent.err.log</string>
</dict>
</plist>
```

Replace `/Users/example` with the target user's home directory. Do not commit a local user's absolute path into reusable docs or templates.

## 3. Add One Launch Condition

Pick the smallest launch condition that matches the job.

Run once when loaded:

```xml
<key>RunAtLoad</key>
<true/>
```

Run every N seconds:

```xml
<key>StartInterval</key>
<integer>3600</integer>
```

Run at a wall-clock time. Missing fields are wildcards:

```xml
<key>StartCalendarInterval</key>
<dict>
  <key>Hour</key>
  <integer>3</integer>
  <key>Minute</key>
  <integer>0</integer>
</dict>
```

Run when a watched path changes:

```xml
<key>WatchPaths</key>
<array>
  <string>/Users/example/input-folder</string>
</array>
```

Use `WatchPaths` carefully. File-system events are race-prone and may arrive while a file is still being written. For ingestion pipelines, make the script idempotent and safe to rerun.

Use `QueueDirectories` when the condition is "directory is non-empty", not "anything changed".

## 4. Load, Run, Inspect

Use modern `launchctl` verbs.

```bash
PLIST="$HOME/Library/LaunchAgents/com.example.my-agent.plist"
LABEL="com.example.my-agent"
DOMAIN="gui/$(id -u)"

plutil -lint "$PLIST"
launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl kickstart -kp "$DOMAIN/$LABEL"
launchctl print "$DOMAIN/$LABEL"
launchctl print-disabled "$DOMAIN"
```

Use `launchctl bootout "$DOMAIN/$LABEL"` only when you have a service target and do not need to refer to the plist path. For file-oriented reloads, path-based `bootout "$DOMAIN" "$PLIST"` is usually clearer.

## 5. Diagnose Failures

Check these in order.

1. Plist syntax:

```bash
plutil -lint "$PLIST"
```

2. File permissions:

```bash
ls -l "$PLIST"
```

User LaunchAgents under `~/Library/LaunchAgents` must be owned by that user and must not be group/world writable.

3. Loaded state:

```bash
launchctl print "$DOMAIN/$LABEL"
```

`launchctl print` is diagnostic text, not a stable machine API. Read it as evidence, not as a structured contract.

4. Disabled state:

```bash
launchctl print-disabled "$DOMAIN"
launchctl enable "$DOMAIN/$LABEL"
```

5. Immediate run:

```bash
launchctl kickstart -kp "$DOMAIN/$LABEL"
```

6. Logs:

```bash
tail -80 "$HOME/Library/Logs/my-agent.out.log"
tail -80 "$HOME/Library/Logs/my-agent.err.log"
```

If the log files are missing, verify that the parent directory exists and is writable by the user running the LaunchAgent.

## 6. Common Root Causes

`PATH` is too small.

LaunchAgent jobs do not inherit your interactive shell config. Put the real executable path in `ProgramArguments`, or set `PATH` in `EnvironmentVariables`.

The script works in Terminal but not under launchd.

Terminal may have a different environment, current directory, TTY, and bootstrap namespace. Add `WorkingDirectory`, explicit env vars, and file-based logs.

The job is present but not loaded.

The plist file existing under `~/Library/LaunchAgents` does not mean launchd loaded it. Run `bootstrap`, then inspect the service target.

The job needs GUI services.

Use a user LaunchAgent in the GUI domain, not a LaunchDaemon. If needed, set `LimitLoadToSessionType` to `Aqua`.

The job should survive crashes.

Use `KeepAlive` only when the process is meant to be long-running or conditionally restarted. Do not use it for a short periodic job that should exit.

The job is a watcher.

Make the script idempotent, debounce if needed, and do not assume a watched file is complete at the moment the job starts.

The machine slept through a timer.

`StartInterval` firings can be missed during sleep. `StartCalendarInterval` runs after wake for missed wall-clock events, coalescing multiple missed intervals into one.

## 7. Report Template

Use this when handing back a LaunchAgent fix.

```text
Label: <label>
Plist: <path>
Domain: gui/<uid>
Validation: plutil -lint <result>
Load: bootstrap/bootout <result>
Run: kickstart <result>
Logs:
- stdout: <path>
- stderr: <path>
Remaining constraints: <none or specific constraints>
```
