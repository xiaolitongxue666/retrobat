#!/usr/bin/env bash
# Download pinned emulators into emulators/ and record sha256 locks.

SYNC_UPDATE=0

cmd_doctor() {
  local release=0
  require_git_bash
  release="$(windows_release)"
  require_curl
  printf '[ok]   windows %s\n' "$release"
  printf '[ok]   git bash %s\n' "$MSYSTEM"
  check_library_link roms "$RETROBAT_ROMS"
  check_library_link bios "$RETROBAT_BIOS"
  ensure_7zr
  printf '[ok]   7zr %s\n' "$SEVENZR"
  bash "$SCRIPT_DIR/retrobat-paths.sh"
}

check_library_link() {
  local name="$1"
  local value="$2"
  local kind target link existing
  local -a info
  mapfile -t info < <(resolve_library "$value" "$name")
  kind="${info[0]}"
  target="${info[1]}"
  link="$ROOT/$name"
  if [[ ! -d "$target" ]]; then
    die "$name library is missing: $target"
  fi
  if [[ "$kind" == "external" ]] && ! paths_equal "$link" "$target"; then
    existing="$(junction_target "$link")"
    if [[ -z "$existing" ]] || ! paths_equal "$existing" "$target"; then
      die "$link is not a junction to $target (run: ./scripts/retro.bash link)"
    fi
  fi
  printf '[ok]   %s %s\n' "$name" "$target"
}

cmd_sync() {
  local line id channel url filename dest members
  require_git_bash
  windows_release >/dev/null
  require_curl
  mkdir -p "$CACHE_DIR" "$LOG_DIR"
  ensure_7zr
  while IFS= read -r line; do
    IFS=$'\t' read -r id channel url filename dest members <<< "$line"
    [[ "$id" == "sevenzip" ]] && continue
    sync_one "$id" "$channel" "$url" "$filename" "$dest" "$members"
  done < <(each_manifest_row)
  printf '[ok]   sync complete\n'
}

ensure_7zr() {
  local url filename dest members archive hash locked
  local line
  mkdir -p "$(dirname "$SEVENZR")"
  line="$(each_manifest_row | awk -F '\t' '$1 == "sevenzip" { print; exit }')"
  [[ -n "$line" ]] || die "sevenzip row missing from manifest"
  IFS=$'\t' read -r _ _ url filename dest members <<< "$line"
  archive="$CACHE_DIR/$filename"
  if [[ ! -f "$SEVENZR" || ! -f "$archive" ]]; then
    download_verified sevenzip pinned "$url" "$archive"
    cp -f "$archive" "$SEVENZR"
  else
    hash="$(sha256_file "$archive")"
    locked="$(read_lock sevenzip || true)"
    if [[ -n "$locked" && "$locked" != "$hash" ]]; then
      die "7zr sha256 mismatch (lock $locked, file $hash)"
    fi
    [[ -n "$locked" ]] || write_lock sevenzip "$hash"
  fi
}

sync_one() {
  local id="$1" channel="$2" url="$3" filename="$4" dest_rel="$5" members="$6"
  local archive dest hash locked tmp
  archive="$CACHE_DIR/$filename"
  dest="$ROOT/$dest_rel"
  if [[ "$SYNC_UPDATE" -eq 1 && "$channel" == "latest" ]]; then
    rm -f "$archive"
  fi
  download_verified "$id" "$channel" "$url" "$archive"
  hash="$(sha256_file "$archive")"
  locked="$(read_lock "$id" || true)"
  if [[ -n "$locked" && "$locked" != "$hash" ]]; then
    die "$id sha256 mismatch (lock $locked, file $hash). For DuckStation run: ./scripts/retro.bash sync --update"
  fi
  mkdir -p "$dest"
  if [[ "$id" == "cores" ]]; then
    extract_cores "$archive" "$dest" "$members"
  elif [[ -z "$members" ]]; then
    extract_app "$archive" "$dest" "$id"
  fi
  printf '[ok]   %s -> %s\n' "$id" "$dest_rel"
}

download_verified() {
  local id="$1" channel="$2" url="$3" archive="$4"
  local hash locked
  if [[ -f "$archive" && "$SYNC_UPDATE" -eq 1 && "$channel" == "latest" ]]; then
    rm -f "$archive"
  fi
  if [[ ! -f "$archive" ]]; then
    mkdir -p "$(dirname "$archive")"
    printf 'download %s\n' "$url"
    curl -fL --retry 3 --retry-delay 2 -o "$archive.part" "$url"
    mv "$archive.part" "$archive"
  fi
  hash="$(sha256_file "$archive")"
  locked="$(read_lock "$id" || true)"
  if [[ -n "$locked" && "$locked" != "$hash" ]]; then
    if [[ "$SYNC_UPDATE" -eq 1 && "$channel" == "latest" ]]; then
      write_lock "$id" "$hash"
      return
    fi
    die "$id sha256 mismatch (lock $locked, file $hash)"
  fi
  if [[ -z "$locked" ]]; then
    write_lock "$id" "$hash"
  fi
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  local dest_win
  mkdir -p "$dest"
  dest_win="$(win_path "$dest")"
  case "${archive##*.}" in
    7z|7Z)
      "$SEVENZR" x "$(win_path "$archive")" "-o${dest_win}" -y >"$LOG_DIR/7zr.log"
      ;;
    zip|ZIP)
      python - "$archive" "$dest" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
      ;;
    *)
      die "unsupported archive: $archive"
      ;;
  esac
}

extract_cores() {
  local archive="$1" dest="$2" members="$3"
  local tmp name found base
  tmp="$CACHE_DIR/cores-extract"
  rm -rf "$tmp"
  extract_archive "$archive" "$tmp"
  mkdir -p "$dest"
  IFS=',' read -r -a names <<< "$members"
  for name in "${names[@]}"; do
    found="$(find "$tmp" -type f -iname "$name" -print -quit)"
    if [[ -z "$found" ]]; then
      die "core not in archive: $name"
    fi
    base="$(basename "$found")"
    cp -f "$found" "$dest/$base"
  done
  rm -rf "$tmp"
}

extract_app() {
  local archive="$1" dest="$2" id="$3"
  local marker tmp found dir
  case "$id" in
    retroarch) marker="retroarch.exe" ;;
    mesen) marker="Mesen.exe" ;;
    duckstation) marker="duckstation*.exe" ;;
    *) marker="" ;;
  esac
  tmp="$CACHE_DIR/${id}-extract"
  rm -rf "$tmp"
  extract_archive "$archive" "$tmp"
  if [[ -n "$marker" ]]; then
    found="$(find "$tmp" -type f -iname "$marker" -print -quit)"
    [[ -n "$found" ]] || die "$id archive has no $marker"
    dir="$(dirname "$found")"
    mkdir -p "$dest"
    if ! paths_equal "$dir" "$dest"; then
      find "$dir" -mindepth 1 -maxdepth 1 -exec cp -a {} "$dest/" \;
    fi
  else
    mkdir -p "$dest"
    find "$tmp" -mindepth 1 -maxdepth 1 -exec cp -a {} "$dest/" \;
  fi
  rm -rf "$tmp"
  case "$id" in
    retroarch) [[ -f "$dest/retroarch.exe" ]] || die "retroarch.exe missing after extract" ;;
    mesen) [[ -f "$dest/Mesen.exe" ]] || die "Mesen.exe missing after extract" ;;
    duckstation)
      find "$dest" -maxdepth 1 -type f -iname 'duckstation*.exe' | grep -q . || die "duckstation exe missing after extract"
      ;;
  esac
}
