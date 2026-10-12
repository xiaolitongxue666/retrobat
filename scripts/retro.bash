#!/usr/bin/env bash
# Manage the Win10/Win11 RetroArch, Mesen, and DuckStation install.
#
#   ./scripts/retro.bash doctor
#   ./scripts/retro.bash link
#   ./scripts/retro.bash sync [--update]
#   ./scripts/retro.bash config
#   ./scripts/retro.bash roms
#   ./scripts/retro.bash test
#   ./scripts/retro.bash play retroarch nes mesen
#   ./scripts/retro.bash play mesen
#   ./scripts/retro.bash play duckstation

set -euo pipefail

SCRIPT_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.bash
source "$SCRIPT_SELF/lib/common.bash"
# shellcheck source=lib/link.bash
source "$SCRIPT_SELF/lib/link.bash"
# shellcheck source=lib/sync.bash
source "$SCRIPT_SELF/lib/sync.bash"
# shellcheck source=lib/config.bash
source "$SCRIPT_SELF/lib/config.bash"
# shellcheck source=lib/roms.bash
source "$SCRIPT_SELF/lib/roms.bash"
# shellcheck source=lib/test.bash
source "$SCRIPT_SELF/lib/test.bash"

load_env

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  doctor) cmd_doctor "$@" ;;
  link) cmd_link "$@" ;;
  sync)
    if [[ "${1:-}" == "--update" ]]; then
      SYNC_UPDATE=1
      shift
    fi
    cmd_sync "$@"
    ;;
  config) cmd_config "$@" ;;
  roms) cmd_roms "$@" ;;
  test) cmd_test "$@" ;;
  play) cmd_play "$@" ;;
  -h|--help|help) usage ;;
  *)
    usage >&2
    die "unknown command: $cmd"
    ;;
esac
