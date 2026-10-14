#!/usr/bin/env bash
# Load, savestate, and standalone launch checks.

REPORT="$LOG_DIR/report.txt"
TEST_OVERLAY="$CONFIG_DIR/retroarch.test.cfg"
FAILED=0

record() {
  printf '%s\n' "$1" | tee -a "$REPORT"
}

pass() { record "PASS $*"; }
fail() { FAILED=1; record "FAIL $*"; }
skip() { record "SKIP $*"; }

core_dll() {
  case "$1" in
    mesen) printf 'mesen_libretro.dll\n' ;;
    fceumm) printf 'fceumm_libretro.dll\n' ;;
    nestopia) printf 'nestopia_libretro.dll\n' ;;
    genesis_plus_gx) printf 'genesis_plus_gx_libretro.dll\n' ;;
    picodrive) printf 'picodrive_libretro.dll\n' ;;
    blastem) printf 'blastem_libretro.dll\n' ;;
    snes9x) printf 'snes9x_libretro.dll\n' ;;
    bsnes) printf 'bsnes_libretro.dll\n' ;;
    swanstation) printf 'swanstation_libretro.dll\n' ;;
    mednafen_psx_hw) printf 'mednafen_psx_hw_libretro.dll\n' ;;
    pcsx_rearmed) printf 'pcsx_rearmed_libretro.dll\n' ;;
    *) die "unknown core: $1" ;;
  esac
}

write_test_overlay() {
  cat > "$TEST_OVERLAY" <<'EOF'
video_fullscreen = "false"
audio_mute_enable = "true"
pause_nonactive = "false"
stdin_cmd_enable = "true"
EOF
}

retroarch_exe() {
  printf '%s\n' "$ROOT/emulators/retroarch/retroarch.exe"
}

mesen_exe() {
  printf '%s\n' "$ROOT/emulators/mesen/Mesen.exe"
}

duckstation_exe() {
  local exe
  exe="$(find "$ROOT/emulators/duckstation" -maxdepth 2 -type f -iname 'duckstation-nogui*.exe' -print -quit 2>/dev/null || true)"
  if [[ -z "$exe" ]]; then
    exe="$(find "$ROOT/emulators/duckstation" -maxdepth 2 -type f -iname 'duckstation-qt*.exe' -print -quit 2>/dev/null || true)"
  fi
  printf '%s\n' "$exe"
}

assert_config() {
  local file="$APPEND_CFG"
  local key
  [[ -f "$file" ]] || { fail "missing $file"; return; }
  for key in 'user_language = "12"' 'video_scale_integer = "true"' 'aspect_ratio_index = "22"' 'input_joypad_driver = "dinput"' 'input_autodetect_enable = "true"'; do
    if grep -qF "$key" "$file"; then
      pass "config $key"
    else
      fail "config missing $key"
    fi
  done
  if grep -q 'savefile_directory' "$file" && grep -q 'savestate_directory' "$file"; then
    pass "config save directories"
  else
    fail "config save directories"
  fi
  if grep -q 'swanstation_GPU_ResolutionScale = "2"' "$CORE_OPTS" \
    && grep -q 'swanstation_GPU_PGXPEnable = "true"' "$CORE_OPTS" \
    && grep -q 'swanstation_GPU_PGXPCulling = "true"' "$CORE_OPTS" \
    && grep -q 'swanstation_GPU_PGXPTextureCorrection = "true"' "$CORE_OPTS" \
    && grep -q 'swanstation_GPU_PGXPDepthBuffer = "true"' "$CORE_OPTS"; then
    pass "swanstation 2x PGXP"
  else
    fail "swanstation core options"
  fi
  local ini="$ROOT/emulators/duckstation/settings.ini"
  if [[ -f "$ini" ]] && grep -q 'ResolutionScale = 2' "$ini" \
    && grep -q 'PGXPEnable = true' "$ini" \
    && grep -q 'PGXPCulling = true' "$ini" \
    && grep -q 'PGXPTextureCorrection = true' "$ini" \
    && grep -q 'PGXPDepthBuffer = true' "$ini" \
    && grep -q 'SearchDirectory = \.\.\\\.\.\\bios' "$ini"; then
    pass "duckstation 2x PGXP bios"
  else
    fail "duckstation settings"
  fi
}

check_locks() {
  local line id channel url filename dest members archive hash locked
  while IFS= read -r line; do
    IFS=$'\t' read -r id channel url filename dest members <<< "$line"
    archive="$CACHE_DIR/$filename"
    if [[ ! -f "$archive" ]]; then
      fail "archive missing $id"
      continue
    fi
    hash="$(sha256_file "$archive")"
    locked="$(read_lock "$id" || true)"
    if [[ "$locked" == "$hash" ]]; then
      pass "sha256 $id"
    else
      fail "sha256 $id"
    fi
  done < <(each_manifest_row)
  [[ -f "$(retroarch_exe)" ]] && pass "retroarch.exe" || fail "retroarch.exe"
  [[ -f "$(mesen_exe)" ]] && pass "Mesen.exe" || fail "Mesen.exe"
  [[ -n "$(duckstation_exe)" ]] && pass "duckstation exe" || fail "duckstation exe"
}

run_retroarch() {
  local core="$1" rom="$2" system="$3" log="$4"
  local dll save_cfg exe
  dll="$ROOT/emulators/retroarch/cores/$(core_dll "$core")"
  exe="$(retroarch_exe)"
  [[ -f "$dll" && -f "$exe" ]] || return 2
  save_cfg="$(system_save_append "$system" "$core")"
  local merged="$CONFIG_DIR/retroarch.run.cfg"
  printf '%s\n' 'savestate_auto_load = "false"' > "$merged"
  grep -v -E '^(savefile_directory|savestate_directory|savestate_auto_load) ' "$APPEND_CFG" >> "$merged"
  cat "$save_cfg" "$TEST_OVERLAY" >> "$merged"
  cat >> "$merged" <<'EOF'
network_cmd_enable = "true"
network_cmd_port = "55355"
config_save_on_exit = "false"
sort_savestates_enable = "false"
sort_savefiles_enable = "false"
EOF
  "$exe" \
    -L "$(win_path "$dll")" \
    "$(win_path "$rom")" \
    --appendconfig="$(win_path "$merged")" \
    --verbose >"$log" 2>&1 &
  local pid=$!
  sleep 8
  python - <<'PY'
import socket, time
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto(b"SAVE_STATE\n", ("127.0.0.1", 55355))
time.sleep(2)
for _ in range(3):
    sock.sendto(b"QUIT\n", ("127.0.0.1", 55355))
    time.sleep(0.5)
PY
  local elapsed=0
  while (( elapsed < 20 )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return $?
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  taskkill //F //IM retroarch.exe >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
  return 1
}

launch_core() {
  local system="$1" core="$2"
  local rom log stamp state
  rom="$(cache_file "$system" || true)"
  if [[ -z "$rom" ]]; then
    fail "$system/$core image"
    return
  fi
  log="$LOG_DIR/${system}-${core}.log"
  stamp="$LOG_DIR/.stamp-${system}-${core}"
  touch "$stamp"
  set +e
  run_retroarch "$core" "$rom" "$system" "$log"
  set -e
  if [[ ! -f "$log" ]]; then
    fail "$system/$core no log"
    return
  fi
  if grep -qiE 'Failed to load|Fatal error|does not have a valid' "$log"; then
    fail "$system/$core load"
    return
  fi
  if ! grep -qiE 'Loading content file|正在加载游戏文件|Loading rom:|跳过游戏加载' "$log"; then
    fail "$system/$core load marker"
    return
  fi
  if [[ "$system" == "psx" ]]; then
    if grep -qiE 'No BIOS image found|BIOS image not found|Could not find BIOS|Using HLE BIOS|HLE BIOS|未找到 BIOS|没有找到 BIOS' "$log"; then
      fail "$system/$core bios"
      return
    fi
    if ! grep -qiE 'Firmware found:|found BIOS file:|Console Region: NTSC-U' "$log"; then
      fail "$system/$core bios"
      return
    fi
    local bios_line
    bios_line="$(grep -iE 'Firmware found:|found BIOS file:|Console Region:' "$log" | head -n 1)"
    record "INFO $system/$core ${bios_line}"
  fi
  state="$(find "$ROOT/saves/$system/$core" -type f -name '*.state*' -newer "$stamp" -print -quit 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    fail "$system/$core savestate"
    return
  fi
  pass "$system/$core"
  if [[ -z "${JOYPAD_SEEN:-}" ]]; then
    JOYPAD_SEEN=1
    if grep -qiE '\[Input\] Device|autoconfig:|Controller port [0-9]+' "$log"; then
      pass "gamepad mentioned in $system/$core log"
    else
      skip "gamepad not connected"
    fi
  fi
}

bios_ready() {
  local log="$LOG_DIR/bios-verify.log"
  local rc
  set +e
  bash "$SCRIPT_DIR/ps1-bios-verify.sh" >"$log" 2>&1
  rc=$?
  set -e
  record "INFO bios-verify exit=$rc"
  local line
  while IFS= read -r line; do
    record "INFO ${line}"
  done < <(grep -E 'physical path|recognized,|^\[(ok|\?\?|miss)\]|^  (NTSC-|PAL )' "$log" || true)
  if [[ "$rc" -ne 0 ]]; then
    skip "ps1 disc boot (bios verify exit $rc)"
    return 1
  fi
  # %-7s pads "NTSC-U" so the line is "NTSC-U  [ok]", not a single space.
  if ! grep -Eq 'NTSC-U[[:space:]]+\[ok\]' "$log"; then
    skip "ps1 disc boot (NTSC-U bios missing)"
    return 1
  fi
  pass "ps1 bios NTSC-U"
  return 0
}

process_stays_up() {
  local exe="$1"
  shift
  local arg_win rc
  [[ -f "$exe" ]] || return 2
  arg_win="$(win_path "$1")"
  set +e
  powershell.exe -NoProfile -Command "
    \$name = [IO.Path]::GetFileNameWithoutExtension('$(win_path "$exe")')
    \$p = Start-Process -FilePath '$(win_path "$exe")' -WorkingDirectory '$(win_path "$(dirname "$exe")")' -ArgumentList @('$arg_win') -PassThru
    Start-Sleep -Seconds 4
    \$alive = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.ProcessName -like (\$name + '*') })
    if (\$alive.Count -lt 1) { exit 1 }
    \$alive | Stop-Process -Force
    exit 0
  "
  rc=$?
  set -e
  return "$rc"
}

duckstation_boot() {
  local exe="$1" rom="$2"
  local log="$LOG_DIR/duckstation-boot.log"
  local out="$LOG_DIR/duckstation-boot.out"
  local file_log="$ROOT/emulators/duckstation/duckstation.log"
  local rc
  : > "$log"
  : > "$out"
  rm -f "$file_log" "$LOG_DIR/duckstation.log"
  set +e
  powershell.exe -NoProfile -Command "
    \$p = Start-Process -FilePath '$(win_path "$exe")' -WorkingDirectory '$(win_path "$(dirname "$exe")")' -ArgumentList @('-batch','-nogui','-nofullscreen','-earlyconsole','-fastboot','$(win_path "$rom")') -RedirectStandardOutput '$(win_path "$out")' -RedirectStandardError '$(win_path "$log")' -PassThru
    Start-Sleep -Seconds 12
    \$name = [IO.Path]::GetFileNameWithoutExtension('$(win_path "$exe")')
    if (Test-Path -LiteralPath '$(win_path "$file_log")') {
      Copy-Item -LiteralPath '$(win_path "$file_log")' -Destination '$(win_path "$LOG_DIR/duckstation.log")' -Force
    }
    \$alive = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.ProcessName -like (\$name + '*') })
    if (\$alive.Count -lt 1) { exit 1 }
    \$alive | Stop-Process -Force
    exit 0
  "
  rc=$?
  set -e
  if [[ -f "$file_log" && ! -f "$LOG_DIR/duckstation.log" ]]; then
    cp -f "$file_log" "$LOG_DIR/duckstation.log"
  fi
  local bios_line
  if grep -qiE 'No BIOS image found|BIOS image not found|No BIOS images found' "$log" "$out" "$LOG_DIR/duckstation.log" 2>/dev/null; then
    record "INFO duckstation bios missing"
    return 1
  fi
  if [[ -f "$LOG_DIR/duckstation.log" ]] \
    && grep -q 'Using BIOS:' "$LOG_DIR/duckstation.log" \
    && grep -q 'BIOS Region: NTSC-U' "$LOG_DIR/duckstation.log"; then
    bios_line="$(grep 'Using BIOS:' "$LOG_DIR/duckstation.log" | head -n 1)"
    record "INFO duckstation ${bios_line}"
    return 0
  fi
  record "INFO duckstation bios not confirmed"
  return 1
}

cmd_play() {
  local mode="${1:-}" system core rom exe
  case "$mode" in
    retroarch)
      system="${2:-}"
      core="${3:-}"
      [[ -n "$system" && -n "$core" ]] || die "usage: play retroarch <system> <core>"
      rom="$(cache_file "$system")" || die "no cached image for $system (run: ./scripts/retro.bash roms)"
      "$(retroarch_exe)" \
        -L "$(win_path "$ROOT/emulators/retroarch/cores/$(core_dll "$core")")" \
        "$(win_path "$rom")" \
        --appendconfig="$(win_path "$APPEND_CFG")" \
        --appendconfig="$(win_path "$(system_save_append "$system")")"
      ;;
    mesen)
      rom="$(cache_file nes)" || die "no cached nes image"
      "$(mesen_exe)" "$(win_path "$rom")"
      ;;
    duckstation)
      rom="$(cache_file psx)" || die "no cached psx cue"
      exe="$(duckstation_exe)"
      [[ -n "$exe" ]] || die "duckstation exe missing"
      "$exe" "$(win_path "$rom")"
      ;;
    *)
      die "usage: play retroarch <system> <core> | play mesen | play duckstation"
      ;;
  esac
}

cmd_test() {
  local rom exe
  mkdir -p "$LOG_DIR" "$CONFIG_DIR"
  : > "$REPORT"
  cmd_config
  write_test_overlay
  assert_config
  check_locks
  if ! cache_file nes >/dev/null 2>&1; then
    fail "rom cache missing (run: ./scripts/retro.bash roms)"
  fi
  launch_core nes mesen
  launch_core nes fceumm
  launch_core nes nestopia
  launch_core megadrive genesis_plus_gx
  launch_core megadrive picodrive
  launch_core megadrive blastem
  launch_core snes snes9x
  launch_core snes bsnes
  if bios_ready; then
    launch_core psx swanstation
    launch_core psx mednafen_psx_hw
    launch_core psx pcsx_rearmed
    rom="$(cache_file psx || true)"
    exe="$(duckstation_exe)"
    if [[ -n "$rom" && -n "$exe" ]] && duckstation_boot "$exe" "$rom"; then
      pass "duckstation cue"
    else
      fail "duckstation cue"
    fi
  fi
  rom="$(cache_file nes || true)"
  if [[ -n "$rom" ]] && process_stays_up "$(mesen_exe)" "$rom"; then
    pass "mesen exe"
  else
    fail "mesen exe"
  fi
  printf 'report %s\n' "$REPORT"
  return "$FAILED"
}
