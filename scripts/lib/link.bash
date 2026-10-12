#!/usr/bin/env bash
# Create or check roms/ and bios/ from .env.

cmd_link() {
  local status=0
  link_one roms "$RETROBAT_ROMS" || status=1
  link_one bios "$RETROBAT_BIOS" || status=1
  return "$status"
}

remove_junction() {
  local path_win
  path_win="$(win_path "$1")"
  powershell.exe -NoProfile -Command "Remove-Item -LiteralPath '$path_win' -Force"
}

link_one() {
  local name="$1"
  local value="$2"
  local kind target link existing
  local -a info

  mapfile -t info < <(resolve_library "$value" "$name")
  kind="${info[0]}"
  target="${info[1]}"
  link="$ROOT/$name"

  if [[ "$kind" == "internal" ]]; then
    if [[ -n "$(junction_target "$link")" ]]; then
      printf '[miss] %s is a junction, but .env keeps this library inside the repository\n' "$link"
      return 1
    fi
    mkdir -p "$target"
    printf '[ok]   %s %s\n' "$name" "$target"
    return 0
  fi

  if [[ ! -d "$target" ]]; then
    printf '[miss] %s -> %s\n' "$name" "$target"
    return 1
  fi

  if paths_equal "$link" "$target"; then
    printf '[ok]   %s %s\n' "$name" "$target"
    return 0
  fi

  existing="$(junction_target "$link")"
  if [[ -n "$existing" ]]; then
    if paths_equal "$existing" "$target"; then
      printf '[ok]   %s -> %s\n' "$name" "$target"
      return 0
    fi
    remove_junction "$link"
  elif [[ -d "$link" ]]; then
    if find "$link" -mindepth 1 -print -quit | grep -q .; then
      die "$link already has files and .env points at $target"
    fi
    remove_junction "$link"
  elif [[ -e "$link" ]]; then
    die "$link exists and is not a directory"
  fi

  local link_win target_win
  link_win="$(win_path "$link")"
  target_win="$(win_path "$target")"
  powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$link_win' -Target '$target_win' | Out-Null"
  printf '[ok]   %s -> %s\n' "$name" "$target"
}
