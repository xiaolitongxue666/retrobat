#!/usr/bin/env bash
# RetroBat path helper — locate BIOS / ROMS directories of a RetroBat install.
#
# Usage:
#   retrobat-paths.sh                    # show all key directories
#   retrobat-paths.sh roms               # show roms dir
#   retrobat-paths.sh bios               # show bios dir
#   retrobat-paths.sh roms <system>      # show roms dir of one system
#   retrobat-paths.sh check <system>     # check roms + bios for one system
#   retrobat-paths.sh list               # list all system ids from systems_names.lst
#
# The RetroBat root is auto-detected: the script walks up from its own location
# looking for RetroBuild.exe / build.ini / system/configgen, or you can force it
# with RETROBAT_ROOT=/path/to/RetroBat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_root() {
  if [[ -n "${RETROBAT_ROOT:-}" ]]; then
    printf '%s\n' "${RETROBAT_ROOT%/}"
    return
  fi
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" && "$dir" != "." ]]; do
    if [[ -f "$dir/build.ini" || -f "$dir/RetroBuild.exe" || -d "$dir/system/configgen" ]]; then
      printf '%s\n' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "$SCRIPT_DIR/.."
}

ROOT="$(cd "$(detect_root)" && pwd)"
BIOS_DIR="$ROOT/bios"
ROMS_DIR="$ROOT/roms"
SYSTEMS_LST="$ROOT/system/configgen/systems_names.lst"

# System ids that live in roms\ but are not listed in systems_names.lst
EXTRA_SYSTEMS=(cgenius quake quake2 singe sonicretro sonic-mania switchupdates vpinball halflife)

physical_target() {
  local path="$1"
  local win target
  [[ -e "$path" || -L "$path" ]] || return 0
  if ! command -v powershell.exe >/dev/null 2>&1; then
    if [[ -L "$path" ]]; then
      readlink "$path"
    fi
    return 0
  fi
  win="$(cygpath -w "$path" 2>/dev/null || printf '%s' "$path")"
  win="${win//\'/\'\'}"
  target="$(powershell.exe -NoProfile -Command "\$i = Get-Item -LiteralPath '$win' -Force -ErrorAction SilentlyContinue; if (\$i -and (\$i.Attributes -band [IO.FileAttributes]::ReparsePoint) -and \$i.Target) { \$i.Target }" | tr -d '\r')"
  printf '%s' "$target"
}

show_all() {
  local physical
  echo "RetroBat root : $ROOT"
  echo "BIOS          : $BIOS_DIR"
  echo "ROMS          : $ROMS_DIR"
  echo "  saves       : $ROOT/saves"
  echo "  cheats      : $ROOT/cheats"
  echo "  emulators   : $ROOT/emulators"
  echo "  screenshots : $ROOT/screenshots"
  echo "  system      : $ROOT/system"
  echo "  user        : $ROOT/user"
  echo
  for d in "$BIOS_DIR" "$ROMS_DIR"; do
    if [[ -d "$d" || -L "$d" ]]; then
      printf '[ok]   %s\n' "$d"
      physical="$(physical_target "$d")"
      if [[ -n "$physical" ]]; then
        printf '       -> %s\n' "$physical"
      fi
    else
      printf '[miss] %s\n' "$d"
    fi
  done
}

list_systems() {
  if [[ -f "$SYSTEMS_LST" ]]; then
    grep -v '^[[:space:]]*$' "$SYSTEMS_LST" | tr -d '\r'
  fi
  printf '%s\n' "${EXTRA_SYSTEMS[@]}"
}

require_arg() {
  if [[ -z "${1:-}" ]]; then
    echo "error: missing <system> argument" >&2
    exit 2
  fi
}

cmd="${1:-all}"
case "$cmd" in
  all|"")
    show_all
    ;;
  bios)
    echo "$BIOS_DIR"
    ;;
  roms)
    if [[ -n "${2:-}" ]]; then
      echo "$ROMS_DIR/$2"
    else
      echo "$ROMS_DIR"
    fi
    ;;
  saves)
    echo "$ROOT/saves"
    ;;
  list)
    list_systems
    ;;
  check)
    require_arg "${2:-}"
    sys="$2"
    rom_path="$ROMS_DIR/$sys"
    bis_path="$BIOS_DIR/$sys"
    status=0
    if [[ -d "$rom_path" ]]; then
      echo "[ok]   roms : $rom_path"
    else
      echo "[miss] roms : $rom_path"
      status=1
    fi
    if [[ -d "$bis_path" ]]; then
      echo "[ok]   bios : $bis_path"
    else
      echo "[warn] bios : $bis_path (many systems share bios\\ root instead)"
    fi
    exit $status
    ;;
  -h|--help|help)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "error: unknown command '$cmd' (try --help)" >&2
    exit 2
    ;;
esac
