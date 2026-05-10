# codex-multi-account

Use multiple Codex accounts on one machine without modifying the official Codex CLI.

This project installs a small reversible wrapper around `codex`. The official Codex binary stays untouched and updateable. Each account gets its own auth/state/cache/logs, while all accounts can see the same session history.

## Quick Start

```bash
git clone https://github.com/muzahidulislamhadi/codex-multi-account.git
cd codex-multi-account
./start-multi-codex.sh
source ~/.bashrc
```

Add your first account:

```bash
codex as personal login
```

That creates a profile named `personal`, logs it in, and makes it the default because it is the first profile.

Use Codex normally:

```bash
codex
codex resume
codex exec "summarize this repo"
```

All plain `codex ...` commands use the default profile.

## Add More Accounts

Add a work account:

```bash
codex as work login
```

Add a client account:

```bash
codex as client-a login
```

Add a QA account:

```bash
codex as qa login
```

The pattern is always:

```bash
codex as <profile-name> login
```

Profile names may contain letters, numbers, dots, underscores, and dashes.

Good profile names:

```text
personal
work
client-a
client.alpha
qa
```

## Switch Accounts

After a profile exists, use it by name:

```bash
codex personal
codex work
codex client-a
```

Run any Codex command under a specific account:

```bash
codex personal resume
codex work exec "review this PR"
codex client-a login status
codex qa --version
```

Resume a specific session under a specific account:

```bash
codex work resume 019e0a66-d990-7671-a85e-1f9f0838b49c
```

## Default Account

Show the current default:

```bash
codex default
```

Set the default:

```bash
codex default work
```

Now these commands run under `work`:

```bash
codex
codex login
codex resume
codex exec "explain this codebase"
```

So default mode behaves like normal official Codex usage, except the data is stored in that profile's isolated `CODEX_HOME`.

## List Accounts

```bash
codex accounts
```

Example:

```text
personal      logged-in      default
work          logged-in
client-a      logged-in
qa            not-logged-in
```

## Important Syntax

Create a new profile with `as`:

```bash
codex as work login
```

Use an existing profile directly:

```bash
codex work
```

This is intentional. It keeps the wrapper compatible with future official Codex commands. Unknown future commands are passed to the official Codex binary instead of being treated as profile names.

If you run this before `work` exists:

```bash
codex work login
```

the wrapper will tell you to use:

```bash
codex as work login
```

## How It Works

Official Codex remains wherever it is installed, for example:

```bash
~/.npm-global/bin/codex
```

The wrapper is installed at:

```bash
~/.local/bin/codex
```

Each profile gets a separate Codex home:

```bash
~/.codex-accounts/personal
~/.codex-accounts/work
~/.codex-accounts/client-a
```

These stay separate per account:

```text
auth.json
state_*.sqlite
logs_*.sqlite
cache/
tmp/
config.toml
history.jsonl
```

Only sessions are shared:

```bash
~/.codex-shared/sessions
```

That means accounts stay logged in separately, but they can resume the same session history.

## Session Locking

The wrapper blocks two terminals from explicitly opening the same session ID at the same time:

```bash
codex work resume 019e0a66-d990-7671-a85e-1f9f0838b49c
codex client-a resume 019e0a66-d990-7671-a85e-1f9f0838b49c
```

The second command is blocked while the first one is still alive.

Check locks:

```bash
codex locks
```

Clear stale locks:

```bash
codex clear-stale-locks
```

Picker mode and `resume --last` are not pre-locked because the wrapper cannot know which session Codex will select before Codex starts. For team work, prefer explicit session IDs when resuming important sessions.

## Update Codex

Update the official Codex CLI normally:

```bash
npm i -g @openai/codex@latest
```

The wrapper is outside the official package, so Codex updates do not overwrite it.

## Rollback

The installer creates a backup before changing anything:

```bash
~/.codex-multi-backups/<timestamp>
```

Restore the exact previous single-account setup:

```bash
./clean-multi-codex.sh
```

Restore from a specific backup:

```bash
./clean-multi-codex.sh ~/.codex-multi-backups/20260510-120000
```

Rollback restores:

- `~/.codex`
- `~/.bashrc`
- `~/.local/bin/codex`, if one existed
- `~/.codex-accounts`, if one existed
- `~/.codex-shared`, if one existed
- `~/.codex-default-profile`, if one existed

By default, the cleaner removes the used backup after a successful restore. Keep it for auditing:

```bash
CODEX_MULTI_KEEP_BACKUP=1 ./clean-multi-codex.sh
```

## Verify

Run the isolated test:

```bash
./scripts/verify.sh
```

It uses a fake Codex binary in `/tmp` and does not touch your real Codex setup.

## Advanced Install Options

Most users do not need these.

Prepare profiles during install:

```bash
CODEX_MULTI_PROFILES="personal work qa" ./start-multi-codex.sh
```

Set a default during install:

```bash
CODEX_MULTI_DEFAULT_PROFILE=personal ./start-multi-codex.sh
```

Use a custom backup directory:

```bash
CODEX_MULTI_BACKUP_ROOT="$HOME/backups/codex-multi" ./start-multi-codex.sh
```

## Safety Rules

- Do not run with `sudo`.
- Do not share or symlink `auth.json`.
- Do not share SQLite state or log files.
- Share only the `sessions` directory.
- Use `codex as <profile> login` to add each account.
- Use `codex <profile>` to switch to an existing account.
