#!/usr/bin/env bash
# Write a desktop RetroBat.lnk that runs ./scripts/retro.bash menu.
#
#   ./scripts/desktop-shortcut.bash
#
# A shortcut cannot set environment variables, and require_git_bash exits when
# MSYSTEM is empty. The .lnk therefore targets cmd.exe, which sets
# MSYSTEM=MINGW64 and then starts Git's bin/bash.exe --login. That bash is
# found by walking up from git; usr/bin/bash.exe is not the wrapper. cmd /c
# strips the first and last quote of the argument string.
# The icon is the official resources/retrobat_icon.ico (header 00 00 01 00),
# stored at build/desktop/ and not committed. The desktop folder comes from
# [Environment]::GetFolderPath('Desktop'). Closing RetroArch exits bash and
# the console.

set -euo pipefail

SCRIPT_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.bash
source "$SCRIPT_SELF/lib/common.bash"

ICON_URL="https://raw.githubusercontent.com/RetroBat-Official/retrobat/main/resources/retrobat_icon.ico"
ICON_PATH="$ROOT/build/desktop/retrobat_icon.ico"

find_git_bash() {
  local mixed dir
  command -v git >/dev/null 2>&1 || die "git is required to locate bin/bash.exe"
  mixed="$(cygpath -m "$(command -v git)")"
  dir="$(dirname "$mixed")"
  while [[ -n "$dir" && "$dir" != "." && "$dir" != "/" && ! "$dir" =~ ^[A-Za-z]:$ ]]; do
    if [[ -f "$dir/bin/bash.exe" ]]; then
      cygpath -w "$dir/bin/bash.exe"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  die "Git bin/bash.exe not found"
}

icon_header_ok() {
  local sig
  sig="$(od -An -tx1 -N 4 "$1" | tr -d '[:space:]')"
  [[ "$sig" == "00000100" ]]
}

download_icon() {
  mkdir -p "$(dirname "$ICON_PATH")"
  if [[ -s "$ICON_PATH" ]] && icon_header_ok "$ICON_PATH"; then
    return 0
  fi
  printf 'download %s\n' "$ICON_URL"
  curl -fL --retry 3 --retry-delay 2 -o "$ICON_PATH.part" "$ICON_URL"
  icon_header_ok "$ICON_PATH.part" || die "downloaded file is not an .ico"
  mv "$ICON_PATH.part" "$ICON_PATH"
}

desktop_dir() {
  local desktop
  desktop="$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" | tr -d '\r')"
  desktop="${desktop#"${desktop%%[![:space:]]*}"}"
  desktop="${desktop%"${desktop##*[![:space:]]}"}"
  [[ -n "$desktop" ]] || die "desktop folder not found"
  [[ -d "$(cygpath -u "$desktop")" ]] || die "desktop folder not found: $desktop"
  printf '%s\n' "$desktop"
}

write_shortcut() {
  local bash_win icon_win root_win desktop
  bash_win="$(find_git_bash | tr -d '\r')"
  [[ -n "$bash_win" ]] || die "Git bin/bash.exe not found"
  icon_win="$(win_path "$ICON_PATH")"
  root_win="$(win_path "$ROOT")"
  desktop="$(desktop_dir)"
  RB_LNK="${desktop}\\RetroBat.lnk"
  # cmd.exe /c strips the first and last quote, so MSYSTEM is set before bash --login.
  RB_ARGUMENTS="/d /c \"set MSYSTEM=MINGW64&& \"${bash_win}\" --login -c \"cd '${ROOT}' && ./scripts/retro.bash menu\"\""
  RB_WORKDIR="$root_win"
  RB_ICON="${icon_win},0"
  export RB_LNK RB_ARGUMENTS RB_WORKDIR RB_ICON
  powershell.exe -NoProfile -Command '
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($env:RB_LNK)
    $lnk.TargetPath = Join-Path $env:SystemRoot "System32\cmd.exe"
    $lnk.Arguments = $env:RB_ARGUMENTS
    $lnk.WorkingDirectory = $env:RB_WORKDIR
    $lnk.IconLocation = $env:RB_ICON
    $lnk.Description = "RetroBat"
    $lnk.WindowStyle = 1
    $lnk.Save()
  '
  printf '[ok]   %s\n' "$RB_LNK"
}

load_env
require_git_bash
require_curl
download_icon
write_shortcut
