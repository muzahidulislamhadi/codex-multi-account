#!/usr/bin/env bash
# Install a reversible multi-account wrapper for the official Codex CLI.
set -euo pipefail

MARKER="codex-multi-account-wrapper-v1"
BACKUP_ROOT="${CODEX_MULTI_BACKUP_ROOT:-$HOME/.codex-multi-backups}"
DEFAULT_PROFILE="${CODEX_MULTI_DEFAULT_PROFILE:-}"
INITIAL_PROFILES="${CODEX_MULTI_PROFILES:-}"
ACCOUNTS_HOME="${CODEX_MULTI_ACCOUNTS_HOME:-$HOME/.codex-accounts}"
SHARED_HOME="${CODEX_MULTI_SHARED_HOME:-$HOME/.codex-shared}"
SHARED_SESSIONS="$SHARED_HOME/sessions"
DEFAULT_PROFILE_FILE="$HOME/.codex-default-profile"
WRAPPER_PATH="$HOME/.local/bin/codex"
BASHRC="$HOME/.bashrc"
CURRENT_CODEX_HOME="$HOME/.codex"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

is_profile_name() {
  local profile="${1:-}"
  case "$profile" in
    ""|.|..|*/*|*' '*) return 1 ;;
  esac
  [[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]]
}

resolve_real_codex() {
  local found real

  found="$(command -v codex 2>/dev/null || true)"
  if [ -n "$found" ] && [ -x "$found" ]; then
    if grep -q "$MARKER" "$found" 2>/dev/null; then
      real="$("$found" real 2>/dev/null || true)"
      if [ -n "$real" ] && [ -x "$real" ] && [ "$real" != "$WRAPPER_PATH" ]; then
        printf '%s\n' "$real"
        return 0
      fi
    elif [ "$found" != "$WRAPPER_PATH" ]; then
      printf '%s\n' "$found"
      return 0
    fi
  fi

  for real in \
    "$HOME/.npm-global/bin/codex" \
    "$HOME/.local/share/npm/bin/codex" \
    "/usr/local/bin/codex" \
    "/usr/bin/codex" \
    "/bin/codex"; do
    if [ -x "$real" ] && [ "$real" != "$WRAPPER_PATH" ]; then
      printf '%s\n' "$real"
      return 0
    fi
  done

  return 1
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ] || [ -L "$src" ]; then
    cp -a "$src" "$dst"
  else
    printf 'absent\n' > "$dst.absent"
  fi
}

append_bashrc_block() {
  local tmp
  mkdir -p "$(dirname "$BASHRC")"
  [ -f "$BASHRC" ] || touch "$BASHRC"

  tmp="$(mktemp "${BASHRC}.tmp.XXXXXX")"
  awk '
    /# >>> codex multi-account >>>/ { skip = 1; next }
    /# <<< codex multi-account <<</ { skip = 0; next }
    /# >>> codex account profiles >>>/ { skip = 1; next }
    /# <<< codex account profiles <<</ { skip = 0; next }
    !skip { print }
  ' "$BASHRC" > "$tmp"
  mv "$tmp" "$BASHRC"

  cat >> "$BASHRC" <<'EOF'

# >>> codex multi-account >>>
# Official Codex remains installed separately. This PATH entry makes the
# reversible multi-account wrapper run first.
unset -f codex 2>/dev/null || true
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# <<< codex multi-account <<<
EOF
}

install_wrapper() {
  local real_codex="$1"
  mkdir -p "$HOME/.local/bin"

  cat > "$WRAPPER_PATH" <<EOF
#!/usr/bin/env bash
# $MARKER
set -euo pipefail

REAL_CODEX="$real_codex"
ACCOUNTS_HOME="\${CODEX_MULTI_ACCOUNTS_HOME:-\$HOME/.codex-accounts}"
SHARED_SESSIONS="\${CODEX_MULTI_SHARED_SESSIONS:-\$HOME/.codex-shared/sessions}"
SESSION_LOCKS="\${CODEX_MULTI_SESSION_LOCKS:-\$HOME/.codex-shared/session-locks}"
DEFAULT_PROFILE_FILE="\${CODEX_MULTI_DEFAULT_PROFILE_FILE:-\$HOME/.codex-default-profile}"
ACTIVE_SESSION_LOCK=""

restore_terminal() {
  local tty_path
  tty_path="\$(tty 2>/dev/null || true)"
  if [[ "\$tty_path" == /dev/* && -w "\$tty_path" ]]; then
    printf '\\033[<u\\033[<u\\033[<u\\033[?2004l\\033[?1004l\\033[?1l\\033>' > "\$tty_path" 2>/dev/null || true
    command -v tput >/dev/null 2>&1 && tput rmkx > "\$tty_path" 2>/dev/null || true
    stty sane < "\$tty_path" 2>/dev/null || true
  fi
}

drain_terminal_input() {
  local tty_path _ch
  tty_path="\$(tty 2>/dev/null || true)"
  if [[ "\$tty_path" != /dev/* || ! -r "\$tty_path" ]]; then
    return 0
  fi
  sleep 0.08
  while IFS= read -r -s -t 0.02 -n 1 _ch < "\$tty_path"; do :; done
}

cleanup_terminal_after_tui() {
  restore_terminal
  drain_terminal_input
  restore_terminal
}

cleanup_session_lock() {
  if [ -n "\${ACTIVE_SESSION_LOCK:-}" ] && [ -d "\$ACTIVE_SESSION_LOCK" ]; then
    rm -rf "\$ACTIVE_SESSION_LOCK" 2>/dev/null || true
    ACTIVE_SESSION_LOCK=""
  fi
}

cleanup_on_exit() {
  cleanup_session_lock
  restore_terminal
}

trap 'cleanup_on_exit' EXIT INT TERM

is_reserved_command() {
  case "\${1:-}" in
    ""|as|profile|use|default|accounts|account-home|sessions-home|shared-sessions|locks|clear-stale-locks|real|help|\\
exec|e|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|sandbox|debug|apply|a|resume|fork|cloud|exec-server|features)
      return 0 ;;
    *) return 1 ;;
  esac
}

is_profile_name() {
  local profile="\${1:-}"
  case "\$profile" in
    ""|.|..|*/*|*' '*) return 1 ;;
  esac
  if is_reserved_command "\$profile"; then return 1; fi
  [[ "\$profile" =~ ^[A-Za-z0-9._-]+\$ ]]
}

default_account() {
  local acct=""
  if [ -f "\$DEFAULT_PROFILE_FILE" ]; then
    IFS= read -r acct < "\$DEFAULT_PROFILE_FILE" || acct=""
  fi
  if is_profile_name "\$acct"; then printf '%s\\n' "\$acct"; else return 1; fi
}

require_default_account() {
  local acct
  if acct="\$(default_account)"; then
    printf '%s\\n' "\$acct"
    return 0
  fi
  echo "codex: no default profile is set yet." >&2
  echo "Create one with: codex as <profile> login" >&2
  echo "Or set one with: codex default <profile>" >&2
  return 1
}

ensure_default_account() {
  local acct="\$1"
  if default_account >/dev/null 2>&1; then
    return 0
  fi
  printf '%s\\n' "\$acct" > "\$DEFAULT_PROFILE_FILE"
  chmod 600 "\$DEFAULT_PROFILE_FILE" 2>/dev/null || true
  echo "Default Codex profile set to \$acct" >&2
}

set_default_account() {
  local acct="\${1:-}"
  if ! is_profile_name "\$acct"; then
    echo "Usage: codex default <profile>" >&2
    echo "Profile names may contain only letters, numbers, dot, underscore, and dash." >&2
    return 1
  fi
  ensure_profile "\$acct"
  printf '%s\\n' "\$acct" > "\$DEFAULT_PROFILE_FILE"
  chmod 600 "\$DEFAULT_PROFILE_FILE" 2>/dev/null || true
  echo "Default Codex profile set to \$acct"
}

resolve_real_codex() {
  if [ -x "\$REAL_CODEX" ] && [ "\$REAL_CODEX" != "\$0" ]; then
    printf '%s\\n' "\$REAL_CODEX"
    return 0
  fi
  local candidate
  for candidate in "\$HOME/.npm-global/bin/codex" "\$HOME/.local/share/npm/bin/codex" /usr/local/bin/codex /usr/bin/codex /bin/codex; do
    if [ -x "\$candidate" ] && [ "\$candidate" != "\$0" ] && ! grep -q "$MARKER" "\$candidate" 2>/dev/null; then
      printf '%s\\n' "\$candidate"
      return 0
    fi
  done
  return 1
}

ensure_profile() {
  local acct="\$1" acct_home="\$ACCOUNTS_HOME/\$1"
  local template_acct
  if ! is_profile_name "\$acct"; then
    echo "codex: invalid profile name: \$acct" >&2
    echo "Profile names may contain only letters, numbers, dot, underscore, and dash." >&2
    return 1
  fi
  mkdir -p "\$acct_home" "\$SHARED_SESSIONS" "\$SESSION_LOCKS"
  chmod 700 "\$ACCOUNTS_HOME" "\$acct_home" "\$(dirname "\$SHARED_SESSIONS")" "\$SHARED_SESSIONS" "\$SESSION_LOCKS" 2>/dev/null || true
  if [ -e "\$acct_home/sessions" ] && [ ! -L "\$acct_home/sessions" ]; then
    echo "codex: \$acct_home/sessions exists and is not a symlink." >&2
    return 1
  fi
  if [ "\$(readlink "\$acct_home/sessions" 2>/dev/null || true)" != "\$SHARED_SESSIONS" ]; then
    ln -sfn "\$SHARED_SESSIONS" "\$acct_home/sessions"
  fi
  if [ ! -f "\$acct_home/config.toml" ]; then
    template_acct="\$(default_account || true)"
    if [ -n "\$template_acct" ] && [ -f "\$ACCOUNTS_HOME/\$template_acct/config.toml" ]; then
      cp -a "\$ACCOUNTS_HOME/\$template_acct/config.toml" "\$acct_home/config.toml"
    elif [ -f "\$HOME/.codex/config.toml" ]; then
      cp -a "\$HOME/.codex/config.toml" "\$acct_home/config.toml"
    else
      printf '%s\\n' 'cli_auth_credentials_store = "file"' > "\$acct_home/config.toml"
    fi
    chmod 600 "\$acct_home/config.toml" 2>/dev/null || true
  fi
  ensure_default_account "\$acct"
}

list_accounts() {
  local acct path status default_acct
  mkdir -p "\$ACCOUNTS_HOME"
  default_acct="\$(default_account || true)"
  for path in "\$ACCOUNTS_HOME"/*; do
    [ -d "\$path" ] || continue
    acct="\${path##*/}"
    is_profile_name "\$acct" || continue
    status="not-logged-in"
    [ -f "\$path/auth.json" ] && status="logged-in"
    if [ "\$acct" = "\$default_acct" ]; then
      printf '%s\\t%s\\tdefault\\n' "\$acct" "\$status"
    else
      printf '%s\\t%s\\n' "\$acct" "\$status"
    fi
  done | sort
}

session_lock_key() {
  local session_id="\$1" key
  key="\${session_id//[^A-Za-z0-9._-]/_}"
  [ -n "\$key" ] || return 1
  printf '%s\\n' "\$key"
}

resume_session_arg() {
  local arg
  [ "\${1:-}" = "resume" ] || return 1
  shift
  while [ "\$#" -gt 0 ]; do
    arg="\$1"; shift
    case "\$arg" in
      --) [ "\$#" -gt 0 ] && printf '%s\\n' "\$1" && return 0; return 1 ;;
      -c|--config|--enable|--disable|--remote|--remote-auth-token-env|-i|--image|-m|--model|--local-provider|-p|--profile|-s|--sandbox|-C|--cd|--add-dir|-a|--ask-for-approval)
        [ "\$#" -gt 0 ] && shift ;;
      --config=*|--enable=*|--disable=*|--remote=*|--remote-auth-token-env=*|--image=*|--model=*|--local-provider=*|--profile=*|--sandbox=*|--cd=*|--add-dir=*|--ask-for-approval=*) ;;
      --last|--all|--include-non-interactive|--oss|--dangerously-bypass-approvals-and-sandbox|--search|--no-alt-screen|-h|--help|-V|--version) ;;
      -*) ;;
      *) printf '%s\\n' "\$arg"; return 0 ;;
    esac
  done
  return 1
}

lock_owner_pid() { [ -f "\$1/pid" ] && sed -n '1p' "\$1/pid" 2>/dev/null || true; }

pid_is_alive() {
  local pid="\$1"
  case "\$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "\$pid" 2>/dev/null || ps -p "\$pid" >/dev/null 2>&1
}

write_lock_metadata() {
  local lock_dir="\$1" acct="\$2" session_id="\$3" tty_path
  tty_path="\$(tty 2>/dev/null || true)"
  printf '%s\\n' "\$\$" > "\$lock_dir/pid"
  printf '%s\\n' "\$acct" > "\$lock_dir/account"
  printf '%s\\n' "\$session_id" > "\$lock_dir/session_id"
  printf '%s\\n' "\$(date -Is 2>/dev/null || date)" > "\$lock_dir/started_at"
  printf '%s\\n' "\$tty_path" > "\$lock_dir/tty"
  printf '%s\\n' "\$PWD" > "\$lock_dir/cwd"
}

describe_session_lock() {
  local lock_dir="\$1"
  echo "codex: this session is already open." >&2
  echo "  account: \$(sed -n '1p' "\$lock_dir/account" 2>/dev/null || echo unknown)" >&2
  echo "  pid: \$(sed -n '1p' "\$lock_dir/pid" 2>/dev/null || echo unknown)" >&2
  echo "  tty: \$(sed -n '1p' "\$lock_dir/tty" 2>/dev/null || echo unknown)" >&2
  echo "  cwd: \$(sed -n '1p' "\$lock_dir/cwd" 2>/dev/null || echo unknown)" >&2
  echo "  started: \$(sed -n '1p' "\$lock_dir/started_at" 2>/dev/null || echo unknown)" >&2
  echo "Close that Codex process before resuming the same session again." >&2
}

list_session_locks() {
  local lock_dir pid status
  mkdir -p "\$SESSION_LOCKS"
  for lock_dir in "\$SESSION_LOCKS"/*.lock; do
    [ -d "\$lock_dir" ] || continue
    pid="\$(lock_owner_pid "\$lock_dir")"
    status="stale"; pid_is_alive "\$pid" && status="active"
    printf '%s\\tpid=%s\\taccount=%s\\tsession=%s\\ttty=%s\\tcwd=%s\\n' "\$status" "\${pid:-unknown}" \\
      "\$(sed -n '1p' "\$lock_dir/account" 2>/dev/null || true)" \\
      "\$(sed -n '1p' "\$lock_dir/session_id" 2>/dev/null || true)" \\
      "\$(sed -n '1p' "\$lock_dir/tty" 2>/dev/null || true)" \\
      "\$(sed -n '1p' "\$lock_dir/cwd" 2>/dev/null || true)"
  done
}

clear_stale_session_locks() {
  local lock_dir pid removed=0
  mkdir -p "\$SESSION_LOCKS"
  for lock_dir in "\$SESSION_LOCKS"/*.lock; do
    [ -d "\$lock_dir" ] || continue
    pid="\$(lock_owner_pid "\$lock_dir")"
    if ! pid_is_alive "\$pid"; then rm -rf "\$lock_dir" 2>/dev/null || true; removed=\$((removed + 1)); fi
  done
  echo "Removed \$removed stale Codex session lock(s)."
}

acquire_session_lock() {
  local acct="\$1" session_id key lock_dir owner_pid
  shift
  session_id="\$(resume_session_arg "\$@" || true)"
  [ -n "\$session_id" ] || return 0
  key="\$(session_lock_key "\$session_id")"
  lock_dir="\$SESSION_LOCKS/\$key.lock"
  mkdir -p "\$SESSION_LOCKS"; chmod 700 "\$SESSION_LOCKS" 2>/dev/null || true
  while ! mkdir "\$lock_dir" 2>/dev/null; do
    owner_pid="\$(lock_owner_pid "\$lock_dir")"
    if pid_is_alive "\$owner_pid"; then describe_session_lock "\$lock_dir"; return 75; fi
    rm -rf "\$lock_dir" 2>/dev/null || true
  done
  chmod 700 "\$lock_dir" 2>/dev/null || true
  write_lock_metadata "\$lock_dir" "\$acct" "\$session_id"
  ACTIVE_SESSION_LOCK="\$lock_dir"
}

run_codex() {
  local acct="\$1" real status
  shift
  real="\$(resolve_real_codex)" || { echo "codex: official Codex binary not found." >&2; return 127; }
  acquire_session_lock "\$acct" "\$@"
  set +e
  env CODEX_HOME="\$ACCOUNTS_HOME/\$acct" "\$real" "\$@"
  status=\$?
  set -e
  cleanup_session_lock
  cleanup_terminal_after_tui
  return "\$status"
}

case "\${1:-}" in
  default)
    if [ -n "\${2:-}" ]; then
      set_default_account "\$2"
    elif ! default_account; then
      echo "No default Codex profile is set."
      echo "Create one with: codex as <profile> login"
      exit 1
    fi ;;
  accounts) list_accounts ;;
  account-home)
    [ -n "\${2:-}" ] || { echo "Usage: codex account-home <profile>" >&2; exit 1; }
    is_profile_name "\$2" || { echo "codex: invalid profile name: \$2" >&2; exit 1; }
    echo "\$ACCOUNTS_HOME/\$2" ;;
  sessions-home|shared-sessions) echo "\$SHARED_SESSIONS" ;;
  locks) list_session_locks ;;
  clear-stale-locks) clear_stale_session_locks ;;
  real) resolve_real_codex ;;
  help)
    cat <<'HELP'
Codex multi-account wrapper

Usage:
  codex                         Run the default profile
  codex as <profile> [args...]  Create/use a named profile
  codex <profile> [args...]     Use an existing named profile
  codex default [profile]       Show or set the default profile
  codex accounts                List profiles and login status
  codex account-home <profile>  Print a profile CODEX_HOME
  codex shared-sessions         Print shared sessions directory
  codex locks                   List active/stale explicit-resume locks
  codex clear-stale-locks       Remove stale explicit-resume locks

Profile names may contain only letters, numbers, dot, underscore, and dash.
Unknown first words are passed to the official Codex binary through the default
profile so future Codex commands keep working.
HELP
    ;;
  as|profile|use)
    [ -n "\${2:-}" ] || { echo "Usage: codex \$1 <profile> [codex-args...]" >&2; exit 1; }
    acct="\$2"; shift 2; ensure_profile "\$acct"; run_codex "\$acct" "\$@" ;;
  -*|"")
    acct="\$(require_default_account)"; ensure_profile "\$acct"; run_codex "\$acct" "\$@" ;;
  *)
    if is_reserved_command "\$1"; then
      acct="\$(require_default_account)"; ensure_profile "\$acct"; run_codex "\$acct" "\$@"
    elif is_profile_name "\$1" && [ -d "\$ACCOUNTS_HOME/\$1" ]; then
      acct="\$1"; shift; ensure_profile "\$acct"; run_codex "\$acct" "\$@"
    elif is_profile_name "\$1"; then
      acct="\$(require_default_account)"; ensure_profile "\$acct"; run_codex "\$acct" "\$@"
    else
      echo "codex: invalid profile name or command: \$1" >&2
      echo "Run 'codex help' for usage." >&2
      exit 1
    fi ;;
esac
EOF

  chmod 755 "$WRAPPER_PATH"
}

migrate_profile() {
  local profile="$1"
  local profile_home="$ACCOUNTS_HOME/$profile"

  is_profile_name "$profile" || fail "Invalid profile name: $profile"
  mkdir -p "$profile_home"
  chmod 700 "$profile_home" 2>/dev/null || true

  if [ "$profile" = "$DEFAULT_PROFILE" ] && [ -d "$CURRENT_CODEX_HOME" ]; then
    cp -a "$CURRENT_CODEX_HOME/." "$profile_home/" 2>/dev/null || true
  fi

  if [ -d "$profile_home/sessions" ] && [ ! -L "$profile_home/sessions" ]; then
    mkdir -p "$SHARED_SESSIONS"
    cp -a "$profile_home/sessions/." "$SHARED_SESSIONS/" 2>/dev/null || true
    rm -rf "$profile_home/sessions"
  fi
  ln -sfn "$SHARED_SESSIONS" "$profile_home/sessions"

  if [ ! -f "$profile_home/config.toml" ]; then
    if [ -n "$DEFAULT_PROFILE" ] && [ -f "$ACCOUNTS_HOME/$DEFAULT_PROFILE/config.toml" ]; then
      cp -a "$ACCOUNTS_HOME/$DEFAULT_PROFILE/config.toml" "$profile_home/config.toml"
    elif [ -f "$CURRENT_CODEX_HOME/config.toml" ]; then
      cp -a "$CURRENT_CODEX_HOME/config.toml" "$profile_home/config.toml"
    else
      printf '%s\n' 'cli_auth_credentials_store = "file"' > "$profile_home/config.toml"
    fi
  fi
  chmod 600 "$profile_home/config.toml" 2>/dev/null || true
}

main() {
  [ "${EUID:-$(id -u)}" -ne 0 ] || fail "Do not run this script with sudo/root."
  if [ -n "$DEFAULT_PROFILE" ]; then
    is_profile_name "$DEFAULT_PROFILE" || fail "Invalid CODEX_MULTI_DEFAULT_PROFILE: $DEFAULT_PROFILE"
  fi

  local real_codex ts backup
  real_codex="$(resolve_real_codex)" || fail "Could not find the official Codex binary in PATH or common locations."
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_ROOT/$ts"
  mkdir -p "$backup"

  copy_if_exists "$CURRENT_CODEX_HOME" "$backup/dot-codex"
  copy_if_exists "$ACCOUNTS_HOME" "$backup/dot-codex-accounts"
  copy_if_exists "$SHARED_HOME" "$backup/dot-codex-shared"
  copy_if_exists "$DEFAULT_PROFILE_FILE" "$backup/dot-codex-default-profile"
  copy_if_exists "$WRAPPER_PATH" "$backup/local-bin-codex"
  copy_if_exists "$BASHRC" "$backup/bashrc"

  {
    printf 'MARKER=%q\n' "$MARKER"
    printf 'REAL_CODEX=%q\n' "$real_codex"
    printf 'WRAPPER_PATH=%q\n' "$WRAPPER_PATH"
    printf 'BASHRC=%q\n' "$BASHRC"
    printf 'CURRENT_CODEX_HOME=%q\n' "$CURRENT_CODEX_HOME"
    printf 'ACCOUNTS_HOME=%q\n' "$ACCOUNTS_HOME"
    printf 'SHARED_HOME=%q\n' "$SHARED_HOME"
    printf 'DEFAULT_PROFILE_FILE=%q\n' "$DEFAULT_PROFILE_FILE"
    printf 'DEFAULT_PROFILE=%q\n' "$DEFAULT_PROFILE"
  } > "$backup/manifest.env"

  mkdir -p "$ACCOUNTS_HOME" "$SHARED_SESSIONS" "$SHARED_HOME/session-locks"
  chmod 700 "$ACCOUNTS_HOME" "$SHARED_HOME" "$SHARED_SESSIONS" "$SHARED_HOME/session-locks" 2>/dev/null || true

  if [ -d "$CURRENT_CODEX_HOME/sessions" ] && [ ! -L "$CURRENT_CODEX_HOME/sessions" ]; then
    cp -a "$CURRENT_CODEX_HOME/sessions/." "$SHARED_SESSIONS/" 2>/dev/null || true
  fi

  for profile in $INITIAL_PROFILES; do
    migrate_profile "$profile"
  done
  if [ -n "$DEFAULT_PROFILE" ]; then
    migrate_profile "$DEFAULT_PROFILE"
    printf '%s\n' "$DEFAULT_PROFILE" > "$DEFAULT_PROFILE_FILE"
    chmod 600 "$DEFAULT_PROFILE_FILE" 2>/dev/null || true
  fi

  install_wrapper "$real_codex"
  append_bashrc_block

  ln -sfn "$backup" "$BACKUP_ROOT/latest"

  printf 'Codex multi-account setup complete.\n'
  printf 'Backup: %s\n' "$backup"
  printf 'Official Codex: %s\n' "$real_codex"
  printf 'Wrapper: %s\n' "$WRAPPER_PATH"
  if [ -n "$DEFAULT_PROFILE" ]; then
    printf 'Default profile: %s\n' "$DEFAULT_PROFILE"
  else
    printf 'Default profile: not set yet; first "codex as <profile> ..." will set it.\n'
  fi
  printf '\nOpen a new shell or run: source %s\n' "$BASHRC"
  printf 'Try: codex accounts\n'
}

main "$@"
