#!/usr/bin/env bash
# RetroArch menu: one playlist per system, default cores shared with test.
# Does not pass a ROM or -L, and does not set config_save_on_exit.

cmd_menu() {
  local exe
  exe="$(retroarch_exe)"
  [[ -f "$exe" ]] || die "retroarch.exe missing (run: ./scripts/retro.bash sync)"
  cmd_config
  cmd_roms
  write_playlists
  "$exe" --appendconfig="$(win_path "$APPEND_CFG")"
}

write_playlists() {
  local rom_root cores
  rom_root="$(library_root roms "$RETROBAT_ROMS")"
  cores="$ROOT/emulators/retroarch/cores"
  mkdir -p "$CONFIG_DIR/playlists"
  python - \
    "$rom_root" \
    "$CONFIG_DIR/playlists" \
    "nes" "mesen" "$(mixed_path "$cores/$(core_dll mesen)")" \
    "megadrive" "genesis_plus_gx" "$(mixed_path "$cores/$(core_dll genesis_plus_gx)")" \
    "snes" "snes9x" "$(mixed_path "$cores/$(core_dll snes9x)")" \
    "psx" "swanstation" "$(mixed_path "$cores/$(core_dll swanstation)")" \
    <<'PY'
import json, os, subprocess, sys

root, playlist_dir = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
if len(args) % 3 != 0:
    raise SystemExit("playlist args must be system, core name, core path")

def mixed(path):
    proc = subprocess.run(["cygpath", "-m", path], check=True, capture_output=True)
    text = proc.stdout.decode("utf-8", errors="replace").strip()
    if not text:
        raise SystemExit(f"cygpath returned an empty path for {path}")
    return text

def files_for(system):
    base = os.path.join(root, ".unpacked", system)
    if not os.path.isdir(base):
        return []
    found = []
    for dirpath, _, filenames in os.walk(base):
        for name in filenames:
            if system == "psx" and not name.lower().endswith(".cue"):
                continue
            found.append(os.path.join(dirpath, name))
    return found

os.makedirs(playlist_dir, exist_ok=True)
index = 0
while index < len(args):
    system, core_name, core_path = args[index], args[index + 1], args[index + 2]
    index += 3
    db_name = f"{system}.lpl"
    items = []
    for path in files_for(system):
        label = os.path.splitext(os.path.basename(path))[0]
        items.append({
            "path": mixed(path),
            "label": label,
            "core_path": core_path,
            "core_name": core_name,
            "crc32": "DETECT",
            "db_name": db_name,
        })
    items.sort(key=lambda item: item["label"].casefold())
    document = {
        "version": "1.5",
        "default_core_path": core_path,
        "default_core_name": core_name,
        "label_display_mode": 0,
        "right_thumbnail_mode": 0,
        "left_thumbnail_mode": 0,
        "sort_mode": 0,
        "items": items,
    }
    out = os.path.join(playlist_dir, db_name)
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"[ok]   {out} {len(items)}")
PY
}
