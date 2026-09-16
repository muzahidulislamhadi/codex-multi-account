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

# upgrade cleanup
codex upgrade-cleanup

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
- Explicit `resume <session-id>` also syncs matching per-thread state and current `goals_1.sqlite` goal metadata from the freshest compatible profile DB before Codex starts. Target DB backups are kept in `~/.codex-shared/state-sync-backups`.
- Cross-profile resume state sync is skipped when the session was last written by a different Codex major/minor version, such as `0.142.x` versus `0.143.x`.
- Dynamic tool metadata is not copied across profiles by default. This avoids carrying stale tool namespaces, plugin state, or app-server metadata across accounts and Codex versions. Set `CODEX_MULTI_SYNC_DYNAMIC_TOOLS=1` only when you intentionally want same-version dynamic tool metadata copied.
- Profile launches explicitly pass the caller's working directory to Codex unless `--cd`/`-C` is provided.
- `resume --last` and picker mode are not pre-locked because the selected session is unknown before Codex starts.
- Cursor/VS Code terminals run Codex with `CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT=1` to avoid leaked CSI-u key-release sequences after quitting.
- After updating the official Codex CLI, close long-lived Codex/app-server/exec-server processes and run `codex upgrade-cleanup` so old runtime/tool caches are rebuilt by the new Codex binary.
- Profile names may contain letters, numbers, dot, underscore, and dash.

## Upgrade Canary

The wrapper treats the official Codex binary as a black box. To test a new binary without changing the global install for every profile, set `CODEX_MULTI_REAL_CODEX` for one command:

```bash
CODEX_MULTI_REAL_CODEX="$HOME/.npm-global/bin/codex-0.143.0" codex account1 --version
```

If you use `npx` for a one-off smoke test, call Codex directly with the profile home:

```bash
CODEX_HOME="$HOME/.codex-accounts/account1" npx -y @openai/codex@0.143.0 --version
```

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
