# codex-multi-account

Run multiple Codex accounts on one machine without modifying the official Codex CLI.

The wrapper keeps the official `codex` binary untouched, gives each profile its own auth/state/cache/logs, and shares only session files.

## Install

```bash
git clone https://github.com/muzahidulislamhadi/codex-multi-account.git
cd codex-multi-account
./start-multi-codex.sh
source ~/.bashrc
```

Do not run the installer with `sudo`.

## Core Usage

Create or open a profile:

```bash
codex as account1
```

Create or login a profile:

```bash
codex as account1 login
```

After a profile exists, use it directly:

```bash
codex account1
codex account1 login
codex account1 resume
codex account1 exec "summarize this repo"
```

Add another account:

```bash
codex as account2 login
```

Switch accounts by name:

```bash
codex account1
codex account2
```

The first profile you create becomes the default automatically.

## Default Profile

Show the default:

```bash
codex default
```

Set the default:

```bash
codex default account2
```

Run Codex under the default profile:

```bash
codex
codex login
codex resume
codex exec "review this code"
```

Default mode behaves like normal Codex usage, except the data is stored under the default profile.

## Account Commands

List accounts:

```bash
codex accounts
```

Example:

```text
account1    logged-in    default
account2    logged-in
account3    not-logged-in
```

Show a profile directory:

```bash
codex account-home account1
```

Show the shared sessions directory:

```bash
codex shared-sessions
```

Show wrapper help:

```bash
codex help
```

Show official Codex binary used by the wrapper:

```bash
codex real
```

## Profile Creation Rules

Use `as` when creating a profile:

```bash
codex as account3 login
```

Use direct name after it exists:

```bash
codex account3
```

If you run:

```bash
codex as account3
```

the profile is created and saved even if you do not login. You can login later:

```bash
codex account3 login
```

Allowed profile names:

```text
letters, numbers, dot, underscore, dash
```

Examples:

```text
account1
account2
work-main
client.alpha
```

## Official Codex Commands

All official Codex commands work under either the default profile or a named profile.

Default profile:

```bash
codex login
codex logout
codex resume
codex exec "..."
codex review
codex mcp
codex plugin
codex update
codex --version
```

Named profile:

```bash
codex account1 login
codex account1 logout
codex account1 resume
codex account1 exec "..."
codex account1 review
codex account1 mcp
codex account1 plugin
codex account1 --version
```

Unknown future Codex commands pass through to the official Codex binary under the default profile.

## Session Locks

Explicit session resumes are locked:

```bash
codex account1 resume <session-id>
codex account2 resume <same-session-id>
```

The second command is blocked while the first process is alive.

List locks:

```bash
codex locks
```

Remove stale locks:

```bash
codex clear-stale-locks
```

`resume --last` and picker mode are not pre-locked because the wrapper cannot know the selected session before Codex starts.

## Storage Layout

Profiles:

```bash
~/.codex-accounts/<profile>
```

Shared sessions:

```bash
~/.codex-shared/sessions
```

Separate per profile:

```text
auth.json
state_*.sqlite
logs_*.sqlite
cache/
tmp/
config.toml
history.jsonl
```

## Rollback

Restore the previous single-account Codex setup:

```bash
./clean-multi-codex.sh
```

Keep the rollback backup:

```bash
CODEX_MULTI_KEEP_BACKUP=1 ./clean-multi-codex.sh
```

## Verify

Run an isolated install/rollback test:

```bash
./scripts/verify.sh
```

It uses a fake Codex binary in `/tmp` and does not touch your real Codex setup.
