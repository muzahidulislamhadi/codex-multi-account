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
codex profile-env account1
codex shared-sessions
codex remove-account account2
codex remove-account account1 --force

# locks
codex locks
codex clear-stale-locks

# upgrade cleanup
codex upgrade-cleanup

# provider alignment
codex align-providers
codex align-providers vercel

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
- A profile's `profile.env` is exported for that profile only; see [Per-Profile Environment](#per-profile-environment).
- Explicit `resume <session-id>` also re-stamps the resumed thread with the resuming profile's own `model_provider`; see [Provider Alignment](#provider-alignment).
- Profile names may contain letters, numbers, dot, underscore, and dash.

## Per-Profile Environment

Each profile can carry its own environment variables in `~/.codex-accounts/<profile>/profile.env`. The wrapper exports them just before launching that profile, so a variable set for one account never leaks into the others or into your shell.

```bash
printf 'AI_GATEWAY_API_KEY=%s\n' "$KEY" > "$(codex profile-env account1)"
chmod 600 "$(codex profile-env account1)"
```

The file holds `KEY=value` lines. Blank lines and `#` comments are skipped, a leading `export ` is allowed, and matching single or double quotes around a value are stripped. Values are never evaluated as shell, so `$OTHER` and backticks stay literal. The wrapper warns when the file is readable beyond its owner.

This lets one profile authenticate against an OpenAI-compatible endpoint with an API key while your other profiles keep their normal Codex logins. A complete worked example, using Vercel AI Gateway:

```bash
codex as vercel     # creates ~/.codex-accounts/vercel; quit the TUI once it opens
printf 'AI_GATEWAY_API_KEY=%s\n' "$KEY" > "$(codex profile-env vercel)"
chmod 600 "$(codex profile-env vercel)"
```

`~/.codex-accounts/vercel/config.toml`

```toml
model = "openai/gpt-5.6-sol"
model_provider = "vercel"
model_context_window = 1050000
model_auto_compact_token_limit = 890000
model_reasoning_effort = "high"

[model_providers.vercel]
name = "Vercel AI Gateway"
base_url = "https://ai-gateway.vercel.sh/v1"
env_key = "AI_GATEWAY_API_KEY"
wire_api = "responses"
```

```bash
codex vercel exec --skip-git-repo-check "Reply with exactly: GATEWAY_OK"
```

Points that apply to any API gateway:

- Such a profile needs no `codex login`, so `codex accounts` lists it as `not-logged-in` even though it works.
- Use `wire_api = "responses"` when the endpoint supports the Responses API, and `"chat"` for Chat Completions only. Vercel AI Gateway serves both under `/v1`.
- Vercel addresses models as `creator/model-name`, and the key carries no default model, so `model` must always be set.
- `service_tier` is OpenAI-platform-specific; drop it unless the gateway documents support for it.
- Set the context limits yourself. Codex prints `Model metadata for ... not found` for any model outside its built-in registry and otherwise falls back to conservative defaults.
- Built-in provider ids (`openai`, and the local-model ids) are reserved, so `[model_providers.openai]` is rejected with `Built-in providers cannot be overridden`. Give the gateway its own id, as above. If you would rather keep the built-in provider and only move its endpoint, Codex has a dedicated top-level `openai_base_url` key for that, and it then authenticates from `auth.json` (`codex login --with-api-key`) rather than from `env_key`. Note that `openai_base_url` is honoured only in a `CODEX_HOME` `config.toml`, never in a project-local `.codex/config.toml`.
- `OPENAI_BASE_URL` and `OPENAI_API_KEY` are not read by Codex at runtime. Provider credentials come from the provider's `env_key`, which the wrapper supplies from `profile.env`.

## Provider Alignment

Codex records the provider a session was created with **inside the profile**, and that recorded value wins over `config.toml` when the session is resumed. A gateway profile created after the fact therefore inherits sessions marked for the built-in `openai` provider, and resuming one of them bypasses the gateway entirely:

```
Unexpected status 401 Unauthorized: Missing bearer or basic authentication in header,
url: https://api.openai.com/v1/responses
```

The wrapper handles this automatically for `codex <profile> resume <session-id>`: after syncing the thread it re-stamps that thread with the resuming profile's own `model_provider`, defaulting to `openai` when the profile does not set one. That is symmetric, so resuming a gateway-created session under a normal ChatGPT profile sends it back to `openai`.

Picker mode and `resume --last` choose the session after Codex has already started, so the wrapper cannot stamp them. Run the bulk repair once per profile instead:

```bash
codex align-providers vercel   # one profile
codex align-providers          # every profile
```

Each profile is backed up to `~/.codex-shared/state-sync-backups/<profile>` before it is rewritten, and profiles whose threads already match are left untouched. Override the fallback provider id with `CODEX_MULTI_DEFAULT_MODEL_PROVIDER`.

This reads a Codex-internal database (`<profile>/state_5.sqlite`). The location is stable but the schema is not documented, so the wrapper checks for the table and column first and does nothing when either is missing — a future Codex release may need this updated.

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
