#!/usr/bin/env bash
# Display, language, and save settings for the installed emulators.
# RetroArch 1.22.2 intl/msg_hash.h: RETRO_LANGUAGE_CHINESE_SIMPLIFIED = 12.
# RetroArch 1.22.2 gfx/video_driver.h aspect_ratio: ASPECT_RATIO_CORE = 22.

APPEND_CFG="$CONFIG_DIR/retroarch.append.cfg"
CORE_OPTS="$CONFIG_DIR/retroarch-core-options.cfg"

cmd_config() {
  mkdir -p "$CONFIG_DIR" "$ROOT/saves/nes" "$ROOT/saves/megadrive" "$ROOT/saves/snes" "$ROOT/saves/psx"
  write_retroarch_append
  write_core_options
  write_duckstation_settings
  note_mesen_language
  printf '[ok]   config %s\n' "$APPEND_CFG"
}

write_retroarch_append() {
  local saves bios playlists
  saves="$(mixed_path "$ROOT/saves")"
  # Installed retroarch.cfg leaves system_directory at ":\system", so cores miss the BIOS library.
  bios="$(mixed_path "$ROOT/bios")"
  playlists="$(mixed_path "$CONFIG_DIR/playlists")"
  # Bluetooth 8BitDo Ultimate 2.4G with the rear switch on D is DirectInput.
  mkdir -p "$CONFIG_DIR/playlists"
  cat > "$APPEND_CFG" <<EOF
user_language = "12"
video_scale_integer = "true"
video_aspect_ratio_auto = "false"
aspect_ratio_index = "22"
video_fullscreen = "true"
video_fullscreen_x = "0"
video_fullscreen_y = "0"
system_directory = "${bios}"
savefile_directory = "${saves}"
savestate_directory = "${saves}"
savestate_auto_save = "true"
savestate_auto_load = "true"
stdin_cmd_enable = "true"
input_joypad_driver = "dinput"
input_autodetect_enable = "true"
playlist_directory = "${playlists}"
pause_nonactive = "false"
EOF
}

write_core_options() {
  cat > "$CORE_OPTS" <<'EOF'
swanstation_GPU_ResolutionScale = "2"
swanstation_GPU_PGXPEnable = "true"
swanstation_GPU_PGXPCulling = "true"
swanstation_GPU_PGXPTextureCorrection = "true"
swanstation_GPU_PGXPDepthBuffer = "true"
swanstation_BIOS_PathNTSCJ = "scph5500.bin"
swanstation_BIOS_PathNTSCU = "scph5501.bin"
swanstation_BIOS_PathPAL = "scph5502.bin"
EOF
  local installed="$ROOT/emulators/retroarch/retroarch-core-options.cfg"
  if [[ -d "$ROOT/emulators/retroarch" ]]; then
    cp -f "$CORE_OPTS" "$installed"
  fi
}

write_duckstation_settings() {
  local ini="$ROOT/emulators/duckstation/settings.ini"
  [[ -d "$ROOT/emulators/duckstation" ]] || return 0
  python - "$ini" <<'PY'
import sys
path = sys.argv[1]
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except FileNotFoundError:
    text = ""
updates = {
    "GPU": {
        "ResolutionScale": "2",
        "PGXPEnable": "true",
        "PGXPCulling": "true",
        "PGXPTextureCorrection": "true",
        "PGXPDepthBuffer": "true",
    },
    "BIOS": {
        "SearchDirectory": r"..\..\bios",
    },
    "Logging": {
        "LogLevel": "Info",
        "LogToFile": "true",
        "BIOS": "true",
    },
    "Main": {
        # The first-run wizard never boots a disc or selects a BIOS.
        "SetupWizardIncomplete": "false",
    },
}
lines = text.splitlines()
section = None
seen = {name: set() for name in updates}
out = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped[1:-1]
        out.append(line)
        continue
    if section in updates and "=" in line and not stripped.startswith("#") and not stripped.startswith(";"):
        key = line.split("=", 1)[0].strip()
        if key in updates[section]:
            out.append(f"{key} = {updates[section][key]}")
            seen[section].add(key)
            continue
        if section == "Main" and key == "Language":
            out.append("Language = zh-CN")
            continue
    out.append(line)
for name, keys in updates.items():
    missing = [key for key in keys if key not in seen[name]]
    if not missing:
        continue
    if name not in seen or not any(line.strip() == f"[{name}]" for line in out):
        if out and out[-1] != "":
            out.append("")
        out.append(f"[{name}]")
    for key in missing:
        out.append(f"{key} = {keys[key]}")
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
PY
}

note_mesen_language() {
  local settings="$ROOT/emulators/mesen/settings.json"
  if [[ ! -f "$settings" ]]; then
    printf '[ok]   mesen language key absent\n'
    return
  fi
  if grep -q '"Language"' "$settings"; then
    printf '[ok]   mesen Language key present in %s\n' "$settings"
  else
    printf '[ok]   mesen language key absent\n'
  fi
}

system_save_append() {
  local system="$1"
  local core="${2:-}"
  local sub="$system"
  local file dir
  if [[ -n "$core" ]]; then
    sub="$system/$core"
  fi
  file="$CONFIG_DIR/saves-${sub//\//-}.cfg"
  dir="$(mixed_path "$ROOT/saves/$sub")"
  mkdir -p "$ROOT/saves/$sub"
  cat > "$file" <<EOF
savefile_directory = "${dir}"
savestate_directory = "${dir}"
EOF
  printf '%s\n' "$file"
}
