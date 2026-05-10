#!/usr/bin/env bash
# Revert the reversible multi-account Codex setup installed by start-multi-codex.sh.
set -euo pipefail

MARKER="codex-multi-account-wrapper-v1"
BACKUP_ROOT="${CODEX_MULTI_BACKUP_ROOT:-$HOME/.codex-multi-backups}"
BACKUP="${1:-$BACKUP_ROOT/latest}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

abs_path() {
  local path="$1"
  local dir base

  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
    return 0
  fi

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  dir="$(cd "$dir" && pwd -P)"
  printf '%s/%s\n' "$dir" "$base"
}

restore_path() {
  local backup_path="$1"
  local target_path="$2"
  local absent_marker="$backup_path.absent"

  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    rm -rf "$target_path"
  fi

  if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
    mkdir -p "$(dirname "$target_path")"
    cp -a "$backup_path" "$target_path"
  elif [ -f "$absent_marker" ]; then
    :
  else
    printf 'WARNING: no backup or absent marker for %s\n' "$target_path" >&2
  fi
}

main() {
  [ "${EUID:-$(id -u)}" -ne 0 ] || fail "Do not run this script with sudo/root."
  [ -e "$BACKUP" ] || fail "Backup not found: $BACKUP"
  BACKUP="$(abs_path "$BACKUP")"
  [ -f "$BACKUP/manifest.env" ] || fail "Backup manifest missing: $BACKUP/manifest.env"

  # shellcheck disable=SC1090
  . "$BACKUP/manifest.env"

  : "${WRAPPER_PATH:=$HOME/.local/bin/codex}"
  : "${BASHRC:=$HOME/.bashrc}"
  : "${CURRENT_CODEX_HOME:=$HOME/.codex}"
  : "${ACCOUNTS_HOME:=$HOME/.codex-accounts}"
  : "${SHARED_HOME:=$HOME/.codex-shared}"
  : "${DEFAULT_PROFILE_FILE:=$HOME/.codex-default-profile}"

  if [ -f "$WRAPPER_PATH" ] && grep -q "$MARKER" "$WRAPPER_PATH" 2>/dev/null; then
    rm -f "$WRAPPER_PATH"
  fi

  restore_path "$BACKUP/local-bin-codex" "$WRAPPER_PATH"
  restore_path "$BACKUP/bashrc" "$BASHRC"
  restore_path "$BACKUP/dot-codex" "$CURRENT_CODEX_HOME"
  restore_path "$BACKUP/dot-codex-accounts" "$ACCOUNTS_HOME"
  restore_path "$BACKUP/dot-codex-shared" "$SHARED_HOME"
  restore_path "$BACKUP/dot-codex-default-profile" "$DEFAULT_PROFILE_FILE"

  if [ "${CODEX_MULTI_KEEP_BACKUP:-0}" != "1" ]; then
    if [ -L "$BACKUP_ROOT/latest" ] && [ "$(abs_path "$BACKUP_ROOT/latest")" = "$BACKUP" ]; then
      rm -f "$BACKUP_ROOT/latest"
    fi
    rm -rf "$BACKUP"
    rmdir "$BACKUP_ROOT" 2>/dev/null || true
  fi

  printf 'Codex multi-account setup reverted.\n'
  printf 'Restored backup: %s\n' "$BACKUP"
  printf 'Open a new shell or run: source %s\n' "$BASHRC"
}

main "$@"
