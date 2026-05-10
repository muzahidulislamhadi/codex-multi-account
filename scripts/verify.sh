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
echo "fake-codex $*"
echo "keyboard-enhancement=${CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT:-unset}"
FAKE
chmod +x "$TEST_HOME/bin/codex"

printf 'original-auth\n' > "$TEST_HOME/.codex/auth.json"
printf 'original-config\n' > "$TEST_HOME/.codex/config.toml"
printf 'session\n' > "$TEST_HOME/.codex/sessions/2026/01/01/rollout-test.jsonl"
printf '# test bashrc\n' > "$TEST_HOME/.bashrc"

run_start() {
  HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/start-multi-codex.sh" "$@"
}

run_codex() {
  HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" "$@"
}

run_codex_vscode() {
  HOME="$TEST_HOME" TERM_PROGRAM=vscode PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" "$@"
}

run_clean() {
  HOME="$TEST_HOME" TERM_PROGRAM= PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/clean-multi-codex.sh" "$@"
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
grep -q 'fake-codex --version' /tmp/codex-multi-account-first.out
grep -q 'keyboard-enhancement=unset' /tmp/codex-multi-account-first.out

run_codex_vscode firstacc --version >/tmp/codex-multi-account-vscode.out
grep -q 'keyboard-enhancement=1' /tmp/codex-multi-account-vscode.out

default_profile="$(run_codex default)"
[ "$default_profile" = "firstacc" ]

run_codex accounts >/tmp/codex-multi-account-accounts.out
grep -q $'firstacc\tnot-logged-in\tdefault' /tmp/codex-multi-account-accounts.out

run_codex as secondacc --version >/tmp/codex-multi-account-second.out 2>/tmp/codex-multi-account-second.err
[ -d "$TEST_HOME/.codex-accounts/secondacc" ]
run_codex remove-account secondacc >/tmp/codex-multi-account-remove-second.out
[ ! -e "$TEST_HOME/.codex-accounts/secondacc" ]

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
