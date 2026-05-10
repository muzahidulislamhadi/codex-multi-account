# codex-multi-account

A reversible multi-account profile wrapper for the Codex CLI.

It keeps the official Codex binary untouched, isolates auth/state/cache/logs per account, shares sessions safely, supports default and named profiles, and restores original single-account behavior with a clean rollback script.

## What It Does

- Uses the official `codex` binary as-is.
- Adds a small wrapper at `~/.local/bin/codex`.
- Keeps each account in its own `CODEX_HOME` under `~/.codex-accounts/<profile>`.
- Shares only session JSONL files through `~/.codex-shared/sessions`.
- Keeps `auth.json`, SQLite state, logs, cache, config, and temp files isolated per profile.
- Supports named profiles such as `firstacc`, `work`, `client-a`, `qa`, `u1`, `u2`.
- Automatically makes the first created profile the default on fresh installs.
- Blocks concurrent explicit resumes of the same session ID.
- Creates a rollback backup before changing anything.

## Install

Run as your normal user. Do not use `sudo`.

```bash
git clone https://github.com/muzahidulislamhadi/codex-multi-account.git
cd codex-multi-account
./start-multi-codex.sh
```

Open a new shell, or run:

```bash
source ~/.bashrc
```

## First Account

On a fresh install, no account name is assumed. Create and log into your first profile:

```bash
codex as firstacc login
```

Because it is the first profile, `firstacc` becomes the default automatically.

After that, plain Codex commands use the default profile:

```bash
codex
codex login
codex resume
codex exec "summarize this repo"
```

## Daily Usage

Show the default profile:

```bash
codex default
```

Set the default profile:

```bash
codex default work
```

Create or use a profile explicitly:

```bash
codex as work login
codex as client-a
codex as qa exec "review this change"
```

Use an existing profile by shorthand:

```bash
codex work
codex client-a resume <session-id>
```

List profiles and login status:

```bash
codex accounts
```

Example:

```text
firstacc      logged-in      default
work          logged-in
qa            not-logged-in
```

## Preconfigure Profiles

Teams can prepare profiles during install:

```bash
CODEX_MULTI_DEFAULT_PROFILE=u1 \
CODEX_MULTI_PROFILES="u1 u2 qa client-a" \
./start-multi-codex.sh
```

This is optional. For most fresh installs, the default no-profile setup is cleaner.

## Files And Layout

Official Codex stays wherever it was already installed, for example:

```bash
~/.npm-global/bin/codex
```

The wrapper is installed at:

```bash
~/.local/bin/codex
```

Profiles live under:

```bash
~/.codex-accounts/<profile>
```

Shared session files live under:

```bash
~/.codex-shared/sessions
```

Rollback backups live under:

```bash
~/.codex-multi-backups/<timestamp>
```

## Session Locking

The wrapper prevents two terminals from explicitly resuming the same session ID at the same time:

```bash
codex work resume 019e0a66-d990-7671-a85e-1f9f0838b49c
codex client-a resume 019e0a66-d990-7671-a85e-1f9f0838b49c
```

The second command is blocked while the first process is alive.

Inspect locks:

```bash
codex locks
```

Clear stale locks:

```bash
codex clear-stale-locks
```

Picker mode and `resume --last` are not pre-locked because the wrapper cannot know which session Codex will select before the official binary starts. For important team sessions, prefer explicit session IDs.

## Codex Updates

Update Codex normally:

```bash
npm i -g @openai/codex@latest
```

The wrapper is outside the official package, so Codex updates do not overwrite it. Unknown future Codex commands are passed through to the official binary under the default profile.

## Rollback

Restore the exact previous single-account state:

```bash
./clean-multi-codex.sh
```

Use a specific backup:

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

By default, the cleaner removes the used rollback backup after a successful restore. Keep it for auditing with:

```bash
CODEX_MULTI_KEEP_BACKUP=1 ./clean-multi-codex.sh
```

## Safety Rules

- Do not run with `sudo`.
- Do not share or symlink `auth.json`.
- Do not share SQLite state or log files.
- Share only `sessions`.
- Use `codex as <profile> login` to onboard each account.
- Avoid opening the same explicit session ID in multiple terminals.

## Verify

Run the isolated install/rollback verification:

```bash
./scripts/verify.sh
```

The verification uses a temporary fake Codex binary and does not touch your real Codex setup.
