#!/usr/bin/env bash
# Display, language, and save settings for the installed emulators.
# RetroArch 1.22.2 intl/msg_hash.h: RETRO_LANGUAGE_CHINESE_SIMPLIFIED = 12.
# RetroArch 1.22.2 gfx/video_driver.h aspect_ratio: ASPECT_RATIO_CORE = 22.

APPEND_CFG="$CONFIG_DIR/retroarch.append.cfg"
CORE_OPTS="$CONFIG_DIR/retroarch-core-options.cfg"
JOYPAD_PROFILE="$SCRIPT_DIR/autoconfig/dinput/8BitDo_Ultimate_wireless_Controller.cfg"
JOYPAD_DEVICE_NAME="8BitDo Ultimate wireless Controller for PC"
# USB ID 2dc8:3012. RetroArch reports that pad as the 32-character
# "Bluetooth Wireless Controller" name, which also matches bundled
# profiles such as F30. The alias keeps the same buttons and sets this
# name plus 11720/12306 so it outranks those profiles.
JOYPAD_VID=11720
JOYPAD_PID=12306

cmd_config() {
  mkdir -p "$CONFIG_DIR" "$ROOT/saves/nes" "$ROOT/saves/megadrive" "$ROOT/saves/snes" "$ROOT/saves/psx"
  write_retroarch_append
  install_joypad_autoconfig
  write_core_options
  write_duckstation_settings
  note_mesen_language
  printf '[ok]   config %s\n' "$APPEND_CFG"
}

ultimate_dinput_name() {
  local name_file
  name_file="$CONFIG_DIR/joypad-name.txt"
  rm -f "$name_file"
  JOYPAD_VID="$JOYPAD_VID" JOYPAD_PID="$JOYPAD_PID" \
    JOYPAD_NAME_FILE="$(win_path "$name_file")" \
    powershell.exe -NoProfile -Command '
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class UltimateJoyW {
  public const int MAXPNAMELEN = 32;
  public const int MAX_JOYSTICKOEMVXDNAME = 260;
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct JOYCAPS {
    public ushort wMid;
    public ushort wPid;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAXPNAMELEN)]
    public string szPname;
    public uint wXmin; public uint wXmax;
    public uint wYmin; public uint wYmax;
    public uint wZmin; public uint wZmax;
    public uint wNumButtons;
    public uint wPeriodMin; public uint wPeriodMax;
    public uint wRmin; public uint wRmax;
    public uint wUmin; public uint wUmax;
    public uint wVmin; public uint wVmax;
    public uint wCaps; public uint wMaxAxes; public uint wNumAxes; public uint wMaxButtons;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAXPNAMELEN)]
    public string szRegKey;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAX_JOYSTICKOEMVXDNAME)]
    public string szOEMVxD;
  }
  [DllImport("winmm.dll", CharSet = CharSet.Unicode, EntryPoint = "joyGetDevCapsW")]
  public static extern int joyGetDevCaps(int id, ref JOYCAPS caps, int size);
  [DllImport("winmm.dll")]
  public static extern int joyGetNumDevs();
}
"@
$caps = New-Object UltimateJoyW+JOYCAPS
$size = [Runtime.InteropServices.Marshal]::SizeOf($caps)
$n = [UltimateJoyW]::joyGetNumDevs()
for ($i = 0; $i -lt $n; $i++) {
  $c = New-Object UltimateJoyW+JOYCAPS
  $rc = [UltimateJoyW]::joyGetDevCaps($i, [ref]$c, $size)
  if ($rc -eq 0 -and $c.wMid -eq [int]$env:JOYPAD_VID -and $c.wPid -eq [int]$env:JOYPAD_PID -and $c.szPname) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($env:JOYPAD_NAME_FILE, $c.szPname, $utf8)
    exit 0
  }
}
$pnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
  Where-Object { $_.InstanceId -match "VID_2DC8&PID_3012" -and $_.FriendlyName -match "8BitDo" } |
  Select-Object -First 1 -ExpandProperty FriendlyName
if ($pnp) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($env:JOYPAD_NAME_FILE, $pnp, $utf8)
}
'
  if [[ -s "$name_file" ]]; then
    python -c 'import pathlib,sys; sys.stdout.reconfigure(encoding="utf-8"); print(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[0], end="")' "$name_file"
  fi
}

install_joypad_autoconfig() {
  local dest installed alt rc
  [[ -f "$JOYPAD_PROFILE" ]] || die "missing $JOYPAD_PROFILE"
  dest="$ROOT/emulators/retroarch/autoconfig/dinput"
  installed="$dest/8BitDo_Ultimate_wireless_Controller.cfg"
  alt="$dest/8BitDo_Ultimate_wireless_Controller_alt.cfg"
  mkdir -p "$dest"
  cp -f "$JOYPAD_PROFILE" "$installed"
  ultimate_dinput_name >/dev/null || true
  if [[ -s "$CONFIG_DIR/joypad-name.txt" ]]; then
    set +e
    python - "$JOYPAD_PROFILE" "$alt" "$CONFIG_DIR/joypad-name.txt" "$JOYPAD_DEVICE_NAME" "$JOYPAD_VID" "$JOYPAD_PID" <<'PY'
import pathlib, sys
source, dest, name_file, official, vid, pid = sys.argv[1:]
seen = pathlib.Path(name_file).read_text(encoding="utf-8").splitlines()[0].strip()
if not seen:
    raise SystemExit(3)
# RetroArch's dinput name for this pad is the 32-character Bluetooth
# string, not the winmm "Microsoft ..." name. The bundled F30 profile
# matches that string with affinity 20. Real VID/PID raises affinity to 50.
device = "Bluetooth Wireless Controller   "
if len(device) != 32:
    raise SystemExit("bluetooth device name must be 32 characters")
out = []
replaced = set()
for line in pathlib.Path(source).read_text(encoding="utf-8").splitlines():
    if line.startswith("input_device = "):
        out.append(f'input_device = "{device}"')
        replaced.add("device")
    elif line.startswith("input_vendor_id = "):
        out.append(f'input_vendor_id = "{vid}"')
        replaced.add("vid")
    elif line.startswith("input_product_id = "):
        out.append(f'input_product_id = "{pid}"')
        replaced.add("pid")
    else:
        out.append(line)
if replaced != {"device", "vid", "pid"}:
    raise SystemExit("profile identity keys missing")
if official == device:
    raise SystemExit(3)
pathlib.Path(dest).write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
print(device)
PY
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      printf '[ok]   joypad alias written\n'
    elif [[ "$rc" -ne 3 ]]; then
      die "joypad alias failed"
    fi
  fi
  printf '[ok]   joypad %s\n' "$installed"
}

write_retroarch_append() {
  local saves bios playlists autoconfig
  saves="$(mixed_path "$ROOT/saves")"
  autoconfig="$(mixed_path "$ROOT/emulators/retroarch/autoconfig")"
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
joypad_autoconfig_dir = "${autoconfig}"
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
