#!/usr/bin/env bash
# Shared helpers for scripts/retro.bash. Source this file; do not execute it.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$LIB_DIR/.." && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/emulators.manifest"
LOCK_FILE="$ROOT/build/lock.tsv"
CACHE_DIR="$ROOT/build/cache"
LOG_DIR="$ROOT/build/logs"
CONFIG_DIR="$ROOT/build/config"
SEVENZR="$ROOT/build/tools/7zr.exe"

RETROBAT_ROMS="${RETROBAT_ROMS:-}"
RETROBAT_BIOS="${RETROBAT_BIOS:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

win_path() {
  cygpath -w "$1"
}

mixed_path() {
  cygpath -m "$1"
}

load_env() {
  local file="$ROOT/.env"
  local line key value
  if [[ ! -f "$file" ]]; then
    RETROBAT_ROMS="${RETROBAT_ROMS:-roms}"
    RETROBAT_BIOS="${RETROBAT_BIOS:-bios}"
    return
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      RETROBAT_ROMS) RETROBAT_ROMS="$value" ;;
      RETROBAT_BIOS) RETROBAT_BIOS="$value" ;;
      HTTP_PROXY|http_proxy)
        export http_proxy="$value" HTTP_PROXY="$value"
        ;;
      HTTPS_PROXY|https_proxy)
        export https_proxy="$value" HTTPS_PROXY="$value"
        ;;
    esac
  done < "$file"
  RETROBAT_ROMS="${RETROBAT_ROMS:-roms}"
  RETROBAT_BIOS="${RETROBAT_BIOS:-bios}"
}

require_git_bash() {
  if [[ -z "${MSYSTEM:-}" ]]; then
    die "run this from Git Bash (Windows Terminal). MSYSTEM is empty"
  fi
}

windows_release() {
  local ver digits build
  ver="$(cmd.exe //c ver)"
  ver="${ver//$'\r'/}"
  if [[ "$ver" != *"10.0."* ]]; then
    die "Windows 10 or 11 required, got: $ver"
  fi
  # Chinese Windows prints 版本 in GBK. sed '.' does not cross those bytes,
  # so keep only ASCII digits and dots before taking the build.
  digits="$(printf '%s' "$ver" | tr -cd '0-9.')"
  build="${digits#*10.0.}"
  build="${build%%.*}"
  if [[ ! "$build" =~ ^[0-9]+$ ]]; then
    die "cannot parse Windows build from: $ver"
  fi
  if (( build >= 22000 )); then
    printf '11\n'
  else
    printf '10\n'
  fi
}

require_curl() {
  command -v curl >/dev/null 2>&1 || die "curl is required (Git for Windows includes it)"
}

junction_target() {
  local path="$1"
  local win target
  [[ -e "$path" || -L "$path" ]] || return 0
  win="$(win_path "$path")"
  win="${win//\'/\'\'}"
  target="$(powershell.exe -NoProfile -Command "\$i = Get-Item -LiteralPath '$win' -Force -ErrorAction SilentlyContinue; if (\$i -and \$i.Attributes -band [IO.FileAttributes]::ReparsePoint -and \$i.Target) { \$i.Target }" | tr -d '\r')"
  printf '%s' "$target"
}

paths_equal() {
  local left right
  left="$(win_path "$1" | tr '[:upper:]' '[:lower:]' | tr '\\' '/')"
  right="$(win_path "$2" | tr '[:upper:]' '[:lower:]' | tr '\\' '/')"
  left="${left%/}"
  right="${right%/}"
  [[ "$left" == "$right" ]]
}

# Prints two lines: kind (internal|external) and absolute filesystem path.
resolve_library() {
  local value="$1"
  local name="$2"
  local kind path
  if [[ -z "$value" || "$value" == "$name" || "$value" == "./$name" ]]; then
    printf 'internal\n%s\n' "$ROOT/$name"
    return
  fi
  if [[ "$value" =~ ^[A-Za-z]:[\\/].* || "$value" == //* || "$value" == /* ]]; then
    path="$(cd "$value" 2>/dev/null && pwd)" || path="$value"
    printf 'external\n%s\n' "$path"
    return
  fi
  printf 'internal\n%s\n' "$ROOT/$value"
}

repo_link_path() {
  printf '%s\n' "$ROOT/$1"
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

read_lock() {
  local id="$1"
  [[ -f "$LOCK_FILE" ]] || return 0
  awk -F '\t' -v id="$id" '$1 == id { print $2; exit }' "$LOCK_FILE"
}

write_lock() {
  local id="$1"
  local hash="$2"
  local tmp
  mkdir -p "$(dirname "$LOCK_FILE")"
  tmp="$(mktemp)"
  if [[ -f "$LOCK_FILE" ]]; then
    awk -F '\t' -v id="$id" '$1 != id { print }' "$LOCK_FILE" > "$tmp"
  fi
  printf '%s\t%s\n' "$id" "$hash" >> "$tmp"
  mv "$tmp" "$LOCK_FILE"
}

each_manifest_row() {
  local line
  [[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done < "$MANIFEST"
}
