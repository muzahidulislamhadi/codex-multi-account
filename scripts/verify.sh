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
FAKE
chmod +x "$TEST_HOME/bin/codex"

printf 'original-auth\n' > "$TEST_HOME/.codex/auth.json"
printf 'original-config\n' > "$TEST_HOME/.codex/config.toml"
printf 'session\n' > "$TEST_HOME/.codex/sessions/2026/01/01/rollout-test.jsonl"
printf '# test bashrc\n' > "$TEST_HOME/.bashrc"

HOME="$TEST_HOME" PATH="$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/start-multi-codex.sh" >/tmp/codex-multi-account-start.out

set +e
HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" default >/tmp/codex-multi-account-default-before.out 2>&1
before_status=$?
set -e

if [ "$before_status" -eq 0 ]; then
  echo "expected no default profile on fresh install" >&2
  exit 1
fi

HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" as firstacc --version >/tmp/codex-multi-account-first.out 2>/tmp/codex-multi-account-first.err

grep -q 'Default Codex profile set to firstacc' /tmp/codex-multi-account-first.err
grep -q 'fake-codex --version' /tmp/codex-multi-account-first.out

default_profile="$(HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" default)"
[ "$default_profile" = "firstacc" ]

HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$TEST_HOME/.local/bin/codex" accounts >/tmp/codex-multi-account-accounts.out
grep -q $'firstacc\tnot-logged-in\tdefault' /tmp/codex-multi-account-accounts.out

HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:$TEST_HOME/bin:/usr/bin:/bin" "$ROOT/clean-multi-codex.sh" >/tmp/codex-multi-account-clean.out

[ -f "$TEST_HOME/.codex/auth.json" ]
[ ! -e "$TEST_HOME/.codex-accounts" ]
[ ! -e "$TEST_HOME/.codex-shared" ]
[ ! -e "$TEST_HOME/.codex-default-profile" ]
[ ! -e "$TEST_HOME/.local/bin/codex" ]
[ ! -e "$TEST_HOME/.codex-multi-backups" ]

echo "verify ok"
