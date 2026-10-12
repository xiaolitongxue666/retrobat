#!/usr/bin/env bash
# Verify PS1 BIOS dumps placed in a RetroBat install.
#
# RetroBat's DuckStation profile searches ..\..\bios, i.e. RetroBat\bios\ directly.
# DuckStation identifies a BIOS by content hash only, so the file name does not matter.
#
# Usage:
#   ps1-bios-verify.sh              # scan RetroBat\bios and report
#   ps1-bios-verify.sh <dir>        # scan a custom directory
#
# Hashes come from DuckStation upstream (src/core/bios.cpp, s_image_info_by_hash).
# This script verifies *your own* dump. It does not download or provide BIOS files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASHES="$SCRIPT_DIR/ps1-bios-hashes.csv"

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

BIOS_SIZE=524288   # 512 KiB — the only size DuckStation maps for PS1

if [[ -n "${1:-}" ]]; then
  TARGET="$1"
else
  TARGET="$(cd "$(detect_root)" && pwd)/bios"
fi

if [[ ! -f "$HASHES" ]]; then
  echo "error: hash table not found: $HASHES" >&2
  exit 2
fi

if [[ ! -d "$TARGET" ]]; then
  echo "error: directory not found: $TARGET" >&2
  echo "hint: set RETROBAT_ROOT or pass the bios directory as \$1" >&2
  exit 2
fi

# Git Bash find does not descend into a Windows directory junction.
# PowerShell .Target is a Windows path; cygpath -u it before find/md5sum.
resolve_junction() {
  local path="$1" win physical
  win="$(cygpath -w "$path" 2>/dev/null || printf '%s' "$path")"
  win="${win//\'/\'\'}"
  if ! command -v powershell.exe >/dev/null 2>&1; then
    printf '%s\n' "$path"
    return
  fi
  physical="$(powershell.exe -NoProfile -Command "\$i = Get-Item -LiteralPath '$win' -Force -ErrorAction SilentlyContinue; if (\$i -and (\$i.Attributes -band [IO.FileAttributes]::ReparsePoint) -and \$i.Target) { \$i.Target }" | tr -d '\r')"
  if [[ -n "$physical" ]]; then
    cygpath -u "$physical" 2>/dev/null || printf '%s\n' "$physical"
  else
    printf '%s\n' "$path"
  fi
}

SCAN_DIR="$(resolve_junction "$TARGET")"

echo "BIOS directory : $TARGET"
if [[ "$SCAN_DIR" != "$TARGET" ]]; then
  echo "physical path  : $SCAN_DIR"
fi
echo "hash table     : $HASHES"
echo

declare -A KNOWN=()
declare -A KNOWN_REGION=()
while IFS=',' read -r h version region model; do
  [[ "$h" == "md5" || -z "$h" ]] && continue
  KNOWN["$h"]="$model (v$version, $region)"
  KNOWN_REGION["$h"]="$region"
done < "$HASHES"

mapfile -t FILES < <(find "$SCAN_DIR" -maxdepth 2 -type f \
  \( -iname '*.bin' -o -iname '*.rom' -o -iname '*.img' -o -iname '*.bios' \) | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[miss] no candidate BIOS files (*.bin/*.rom/*.img/*.bios) in $TARGET"
  echo
  echo "Place a BIOS dumped from your own console here. DuckStation matches on content,"
  echo "so any file name works; only the MD5 has to match a known revision."
  exit 1
fi

ok_count=0
unknown_count=0
declare -A REGION_FOUND=()

for f in "${FILES[@]}"; do
  size="$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")"
  hash="$(md5sum "$f" | cut -d' ' -f1)"
  name="$(basename "$f")"

  if [[ -n "${KNOWN[$hash]:-}" ]]; then
    printf '[ok]   %-28s %s\n' "$name" "${KNOWN[$hash]}"
    REGION_FOUND["${KNOWN_REGION[$hash]}"]=1
    ok_count=$((ok_count + 1))
    continue
  fi

  # OpenBIOS is valid but has no fixed hash; it carries a signature at offset 0x78.
  if [[ "$size" == "$BIOS_SIZE" ]] && \
     [[ "$(dd if="$f" bs=1 skip=120 count=8 2>/dev/null)" == "OpenBIOS" ]]; then
    printf '[ok]   %-28s OpenBIOS (open-source, no hash table entry)\n' "$name"
    ok_count=$((ok_count + 1))
    continue
  fi

  unknown_count=$((unknown_count + 1))
  printf '[??]   %-28s unrecognized\n' "$name"
  printf '       md5=%s  size=%s\n' "$hash" "$size"
  if [[ "$size" != "$BIOS_SIZE" ]]; then
    printf '       note: PS1 BIOS must be exactly %s bytes (512 KiB); size looks wrong\n' "$BIOS_SIZE"
  fi
done

echo
printf '%s recognized, %s unrecognized\n' "$ok_count" "$unknown_count"

if [[ "$ok_count" -gt 0 ]]; then
  echo
  echo "Region coverage (DuckStation needs a BIOS matching the disc region):"
  for region in NTSC-U NTSC-J PAL; do
    if [[ -n "${REGION_FOUND[$region]:-}" ]]; then
      printf '  %-7s [ok]\n' "$region"
    else
      printf '  %-7s [--]\n' "$region"
    fi
  done
fi

[[ "$unknown_count" -eq 0 ]] && exit 0 || exit 1
