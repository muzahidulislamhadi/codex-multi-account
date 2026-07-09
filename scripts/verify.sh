#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d /tmp/codex-multi-account-test.XXXXXX)"

cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME/bin" "$TEST_HOME/.codex/sessions/2026/01/01"

cat > "$TEST_HOME/bin/codex" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "codex-cli ${FAKE_CODEX_VERSION:-0.143.0}"
  exit 0
fi
echo "fake-codex $*"
echo "keyboard-enhancement=${CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT:-unset}"
FAKE
chmod +x "$TEST_HOME/bin/codex"
cat > "$TEST_HOME/bin/alternate-codex" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "codex-cli 0.143.0"
  exit 0
fi
echo "alternate-codex $*"
FAKE
chmod +x "$TEST_HOME/bin/alternate-codex"

printf 'original-auth\n' > "$TEST_HOME/.codex/auth.json"
printf 'original-config\n' > "$TEST_HOME/.codex/config.toml"
printf 'session\n' > "$TEST_HOME/.codex/sessions/2026/01/01/rollout-test.jsonl"
printf '# test bashrc\n' > "$TEST_HOME/.bashrc"

run_start() {
  HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/start-multi-codex.sh" "$@"
}

run_codex() {
  env -u CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" "$@"
}

run_codex_vscode() {
  env -u CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT HOME="$TEST_HOME" TERM_PROGRAM=vscode PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" "$@"
}

run_clean() {
  HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/clean-multi-codex.sh" "$@"
}

create_resume_state_db() {
  local db="$1"
  sqlite3 "$db" <<'SQL'
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL,
  updated_at_ms INTEGER,
  cli_version TEXT NOT NULL DEFAULT ''
);
CREATE TABLE thread_dynamic_tools (
  thread_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  input_schema TEXT NOT NULL,
  namespace TEXT,
  PRIMARY KEY(thread_id, position)
);
SQL
}

create_resume_goal_db() {
  local db="$1"
  sqlite3 "$db" <<'SQL'
CREATE TABLE thread_goals (
  thread_id TEXT PRIMARY KEY NOT NULL,
  goal_id TEXT NOT NULL,
  objective TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('active', 'paused', 'blocked', 'usage_limited', 'budget_limited', 'complete')),
  token_budget INTEGER,
  tokens_used INTEGER NOT NULL DEFAULT 0,
  time_used_seconds INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
SQL
}

run_start >/tmp/codex-multi-account-start.out

set +e
run_codex default >/tmp/codex-multi-account-default-before.out 2>&1
before_status=$?
set -e

if [ "$before_status" -eq 0 ]; then
  echo "expected no default profile on fresh install" >&2
  exit 1
fi

run_codex as firstacc --version >/tmp/codex-multi-account-first.out 2>/tmp/codex-multi-account-first.err

grep -q 'Default Codex profile set to firstacc' /tmp/codex-multi-account-first.err
grep -q "fake-codex --cd $PWD --version" /tmp/codex-multi-account-first.out
grep -q 'keyboard-enhancement=unset' /tmp/codex-multi-account-first.out

run_codex_vscode firstacc --version >/tmp/codex-multi-account-vscode.out
grep -q "fake-codex --cd $PWD --version" /tmp/codex-multi-account-vscode.out
grep -q 'keyboard-enhancement=1' /tmp/codex-multi-account-vscode.out

run_codex firstacc --cd /tmp --version >/tmp/codex-multi-account-explicit-cwd.out
grep -q 'fake-codex --cd /tmp --version' /tmp/codex-multi-account-explicit-cwd.out
if grep -q "fake-codex --cd $PWD --cd /tmp" /tmp/codex-multi-account-explicit-cwd.out; then
  echo "wrapper must preserve an explicit working directory" >&2
  exit 1
fi

run_codex firstacc -- --cd >/tmp/codex-multi-account-prompt-cwd.out
grep -q "fake-codex --cd $PWD -- --cd" /tmp/codex-multi-account-prompt-cwd.out

CODEX_MULTI_REAL_CODEX="$TEST_HOME/bin/alternate-codex" run_codex firstacc --version >/tmp/codex-multi-account-real-override.out
grep -q "alternate-codex --cd $PWD --version" /tmp/codex-multi-account-real-override.out

default_profile="$(run_codex default)"
[ "$default_profile" = "firstacc" ]

run_codex accounts >/tmp/codex-multi-account-accounts.out
grep -q $'firstacc\tnot-logged-in\tdefault' /tmp/codex-multi-account-accounts.out

run_codex as secondacc --version >/tmp/codex-multi-account-second.out 2>/tmp/codex-multi-account-second.err
[ -d "$TEST_HOME/.codex-accounts/secondacc" ]
run_codex remove-account secondacc >/tmp/codex-multi-account-remove-second.out
[ ! -e "$TEST_HOME/.codex-accounts/secondacc" ]

run_codex as goalowner --version >/tmp/codex-multi-account-goalowner.out
run_codex as goalreader --version >/tmp/codex-multi-account-goalreader.out
create_resume_state_db "$TEST_HOME/.codex-accounts/goalowner/state_5.sqlite"
create_resume_state_db "$TEST_HOME/.codex-accounts/goalreader/state_5.sqlite"
create_resume_goal_db "$TEST_HOME/.codex-accounts/goalowner/goals_1.sqlite"
create_resume_goal_db "$TEST_HOME/.codex-accounts/goalreader/goals_1.sqlite"
sqlite3 "$TEST_HOME/.codex-accounts/goalowner/state_5.sqlite" <<'SQL'
INSERT INTO threads (id, updated_at, updated_at_ms, cli_version) VALUES ('goal-thread-1', 1000, 1000000, '0.143.0');
INSERT INTO thread_dynamic_tools VALUES ('goal-thread-1', 0, 'stale_tool', 'do not sync by default', '{}', 'stale_namespace');
SQL
sqlite3 "$TEST_HOME/.codex-accounts/goalowner/goals_1.sqlite" <<'SQL'
INSERT INTO thread_goals VALUES ('goal-thread-1', 'goal-id-1', 'sync this goal', 'paused', NULL, 123, 45, 900000, 1000000);
SQL

run_codex goalreader resume goal-thread-1 >/tmp/codex-multi-account-resume-sync.out
grep -q "fake-codex --cd $PWD resume goal-thread-1" /tmp/codex-multi-account-resume-sync.out
[ "$(sqlite3 "$TEST_HOME/.codex-accounts/goalreader/goals_1.sqlite" "SELECT status || ':' || tokens_used FROM thread_goals WHERE thread_id = 'goal-thread-1';")" = "paused:123" ]
[ "$(sqlite3 "$TEST_HOME/.codex-accounts/goalreader/state_5.sqlite" "SELECT count(*) FROM thread_dynamic_tools WHERE thread_id = 'goal-thread-1';")" = "0" ]
find "$TEST_HOME/.codex-shared/state-sync-backups/goalreader" -name 'state_5-before-goal-thread-1-*.sqlite' | grep -q .
find "$TEST_HOME/.codex-shared/state-sync-backups/goalreader" -name 'goals_1-before-goal-thread-1-*.sqlite' | grep -q .

run_codex as dynamicreader --version >/tmp/codex-multi-account-dynamicreader.out
create_resume_state_db "$TEST_HOME/.codex-accounts/dynamicreader/state_5.sqlite"
sqlite3 "$TEST_HOME/.codex-accounts/goalowner/state_5.sqlite" <<'SQL'
INSERT INTO threads (id, updated_at, updated_at_ms, cli_version) VALUES ('dynamic-thread-1', 1100, 1100000, '0.143.0');
INSERT INTO thread_dynamic_tools VALUES ('dynamic-thread-1', 0, 'same_version_tool', 'sync only when explicitly enabled', '{}', 'same_version_namespace');
SQL
CODEX_MULTI_SYNC_DYNAMIC_TOOLS=1 run_codex dynamicreader resume dynamic-thread-1 >/tmp/codex-multi-account-dynamic-sync.out
[ "$(sqlite3 "$TEST_HOME/.codex-accounts/dynamicreader/state_5.sqlite" "SELECT namespace || ':' || name FROM thread_dynamic_tools WHERE thread_id = 'dynamic-thread-1';")" = "same_version_namespace:same_version_tool" ]

run_codex as oldowner --version >/tmp/codex-multi-account-oldowner.out
run_codex as oldreader --version >/tmp/codex-multi-account-oldreader.out
create_resume_state_db "$TEST_HOME/.codex-accounts/oldowner/state_5.sqlite"
create_resume_state_db "$TEST_HOME/.codex-accounts/oldreader/state_5.sqlite"
sqlite3 "$TEST_HOME/.codex-accounts/oldowner/state_5.sqlite" <<'SQL'
INSERT INTO threads (id, updated_at, updated_at_ms, cli_version) VALUES ('old-thread-1', 2000, 2000000, '0.142.0');
SQL
run_codex oldreader resume old-thread-1 >/tmp/codex-multi-account-cross-version.out 2>/tmp/codex-multi-account-cross-version.err
grep -q 'skipping cross-version state sync' /tmp/codex-multi-account-cross-version.err
[ "$(sqlite3 "$TEST_HOME/.codex-accounts/oldreader/state_5.sqlite" "SELECT count(*) FROM threads WHERE id = 'old-thread-1';")" = "0" ]

mkdir -p "$TEST_HOME/.codex-accounts/goalreader/cache/codex_apps_tools"
mkdir -p "$TEST_HOME/.codex-accounts/goalreader/cache/codex_apps_server_info"
mkdir -p "$TEST_HOME/.codex-accounts/goalreader/cache/remote_plugin_catalog"
mkdir -p "$TEST_HOME/.codex-accounts/goalreader/.tmp/app-server-remote-plugin-sync-v1"
touch "$TEST_HOME/.codex-accounts/goalreader/.tmp/plugins.sync.lock"
touch "$TEST_HOME/.codex-accounts/goalreader/.tmp/plugins.sha"
mkdir -p "$TEST_HOME/.codex-accounts/goalreader/app-server-control"
run_codex upgrade-cleanup >/tmp/codex-multi-account-upgrade-cleanup.out
grep -q 'Codex runtime cache path' /tmp/codex-multi-account-upgrade-cleanup.out
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/cache/codex_apps_tools" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/cache/codex_apps_server_info" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/cache/remote_plugin_catalog" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/.tmp/app-server-remote-plugin-sync-v1" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/.tmp/plugins.sync.lock" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/.tmp/plugins.sha" ]
[ ! -e "$TEST_HOME/.codex-accounts/goalreader/app-server-control" ]

set +e
run_codex remove-account firstacc >/tmp/codex-multi-account-remove-default.out 2>&1
remove_default_status=$?
set -e
[ "$remove_default_status" -ne 0 ]
[ -d "$TEST_HOME/.codex-accounts/firstacc" ]

run_codex remove-account firstacc --force >/tmp/codex-multi-account-remove-default-force.out
[ ! -e "$TEST_HOME/.codex-accounts/firstacc" ]
[ ! -e "$TEST_HOME/.codex-default-profile" ]

run_clean >/tmp/codex-multi-account-clean.out

[ -f "$TEST_HOME/.codex/auth.json" ]
[ ! -e "$TEST_HOME/.codex-accounts" ]
[ ! -e "$TEST_HOME/.codex-shared" ]
[ ! -e "$TEST_HOME/.codex-default-profile" ]
[ ! -e "$TEST_HOME/.local/bin/codex" ]
[ ! -e "$TEST_HOME/.codex-multi-backups" ]

echo "verify ok"
