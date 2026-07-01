# Safety Model

LaunchDeck is intentionally conservative. It reads broadly, but writes narrowly.

## Read surface

The inventory reads plist files from:

```text
~/Library/LaunchAgents
/Library/LaunchAgents
/Library/LaunchDaemons
/System/Library/LaunchAgents
/System/Library/LaunchDaemons
```

Read errors are kept on the job summary as parse errors. A bad plist should not
crash the app or stop the rest of the inventory from rendering.

## Write surface

Core app-owned writes are limited to:

```text
~/Library/LaunchAgents/io.github.launchdeck.*.plist
~/Library/Application Support/LaunchDeck/
~/Library/Logs/LaunchDeck/
```

The core model rejects app-owned writes unless the label starts with:

```text
io.github.launchdeck.
```

The SwiftUI editor is also restricted. It only enables write controls for
personal user LaunchAgents that are not Apple system jobs and have no parse
error.

## Read-only surfaces

LaunchDeck does not edit or delete:

```text
/System/Library/*
/Library/LaunchDaemons/*
/Library/LaunchAgents/*
```

These paths can be inspected so a user can understand what is installed, but
operations that would require privileged system management are outside the app.

## launchctl domain

LaunchDeck operates in the current user GUI domain:

```text
gui/<uid>
```

The command wrapper builds service targets as:

```text
gui/<uid>/<label>
```

Labels containing `/` or a null byte are rejected before command execution.

## Validation before save

When the SwiftUI editor saves a plist:

1. It renders the updated plist to a temporary file beside the original.
2. It runs `plutil -lint` on the temporary file.
3. It atomically writes the original plist only if lint passes.
4. It removes the temporary file.

This keeps malformed edits from replacing the active plist.

## Logs

The app displays log paths immediately, but it does not read log contents until
the user clicks a log button. Log preview reads only the tail of the file.

This avoids selection freezes when a launchd job has written a large stdout or
stderr file.

## Live proof

The proof script's live launchd check is opt-in:

```bash
RUN_LIVE_LAUNCHD=1 ./scripts/proof.sh
```

It creates a temporary label matching:

```text
io.github.launchdeck.proof.*
```

It writes temporary files under LaunchDeck-owned user locations, bootstraps the
temporary LaunchAgent, kickstarts it, checks status, boots it out, removes the
generated plist/script/task/marker files, and retains the generated proof log as
evidence.

## What this project does not do

- No privileged helper installation.
- No root daemon management.
- No edits under `/System/Library`.
- No edits under `/Library/LaunchDaemons`.
- No signed installer or notarized release pipeline.
- No parsing of `launchctl print` as a stable automation API.
