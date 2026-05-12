# codex-multi-account

Multi-account profiles for the Codex CLI. Official Codex stays untouched; each profile gets separate auth/state/cache/logs, and only sessions are shared.

## Install

```bash
git clone https://github.com/muzahidulislamhadi/codex-multi-account.git
cd codex-multi-account
./start-multi-codex.sh
source ~/.bashrc
```

Do not use `sudo`.

## Main Commands

```bash
# create/open accounts
codex as account1
codex as account1 login
codex as account2 login

# use existing accounts
codex account1
codex account2 login
codex account2 resume
codex account2 exec "summarize this repo"

# default account
codex default
codex default account2
codex
codex login
codex resume

# list / inspect / remove
codex accounts
codex account-home account1
codex shared-sessions
codex remove-account account2
codex remove-account account1 --force

# locks
codex locks
codex clear-stale-locks

# wrapper info
codex help
codex real
```

The first profile you create becomes the default automatically.

## Creating vs Using

Use `as` to create a profile:

```bash
codex as account1 login
```

After it exists, call it directly:

```bash
codex account1
codex account1 login
```

`codex as account1` without `login` still creates and saves the profile. You can log in later:

```bash
codex account1 login
```

## Official Codex Commands

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

## Notes

- Profiles live in `~/.codex-accounts/<profile>`.
- Shared sessions live in `~/.codex-shared/sessions`.
- `remove-account` deletes only that profile directory; it never deletes shared sessions.
- Removing the default profile requires `--force` or setting another default first.
- Explicit `resume <session-id>` is locked so two accounts cannot open the same session ID at once.
- Explicit `resume <session-id>` also syncs matching per-thread state, including goal metadata, from the freshest profile DB before Codex starts. Target DB backups are kept in `~/.codex-shared/state-sync-backups`.
- `resume --last` and picker mode are not pre-locked because the selected session is unknown before Codex starts.
- Cursor/VS Code terminals run Codex with `CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT=1` to avoid leaked CSI-u key-release sequences after quitting.
- Profile names may contain letters, numbers, dot, underscore, and dash.

## Rollback

```bash
./clean-multi-codex.sh
```

Keep the rollback backup:

```bash
CODEX_MULTI_KEEP_BACKUP=1 ./clean-multi-codex.sh
```

## Verify

```bash
./scripts/verify.sh
```
