#!/usr/bin/env bash
# Unpack one already-present image per system into the ROM library .cache.
# This does not download ROM files.

cmd_roms() {
  local rom_root
  rom_root="$(library_root roms "$RETROBAT_ROMS")"
  [[ -d "$rom_root" ]] || die "ROM library missing: $rom_root"
  python - "$rom_root" "$(win_path "$SEVENZR")" <<'PY'
import os, sys, zipfile, shutil, subprocess
root, sevenzr = sys.argv[1], sys.argv[2]

def archives(system):
    base = os.path.join(root, system)
    if not os.path.isdir(base):
        return
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [name for name in dirnames if name != ".cache"]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if os.path.abspath(path).startswith(os.path.abspath(os.path.join(base, ".cache"))):
                continue
            yield path

def cache_dir(system):
    path = os.path.join(root, ".cache", system)
    os.makedirs(path, exist_ok=True)
    return path

def has_payload(path):
    if not os.path.isdir(path):
        return False
    for dirpath, _, filenames in os.walk(path):
        if filenames:
            return True
    return False

def extract_zip_member(archive, member, dest_dir, dest_name=None):
    os.makedirs(dest_dir, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        data = zf.read(member)
    name = dest_name or os.path.basename(member.replace("\\", "/"))
    out = os.path.join(dest_dir, name)
    with open(out, "wb") as handle:
        handle.write(data)
    print(f"[ok]   {out}")

def pick_zip(system):
    for path in archives(system):
        if zipfile.is_zipfile(path):
            return path
    return None

def nes():
    dest = cache_dir("nes")
    if has_payload(dest):
        print(f"[ok]   {dest} (kept)")
        return
    archive = pick_zip("nes")
    if not archive:
        raise SystemExit("[miss] nes archive")
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            with zf.open(info) as handle:
                magic = handle.read(4)
            if magic == b"NES\x1a":
                extract_zip_member(archive, info.filename, dest, "smoke.nes")
                return
    raise SystemExit("[miss] nes image with iNES header")

def first_member(archive, suffixes):
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            lower = info.filename.lower()
            if lower.endswith(suffixes):
                return info.filename
    return None

def snes():
    dest = cache_dir("snes")
    if has_payload(dest):
        print(f"[ok]   {dest} (kept)")
        return
    archive = pick_zip("snes")
    if not archive:
        raise SystemExit("[miss] snes archive")
    member = first_member(archive, (".smc", ".sfc"))
    if not member:
        raise SystemExit("[miss] snes .smc/.sfc")
    extract_zip_member(archive, member, dest, "smoke.smc")

def is_genesis(data):
    return len(data) > 0x104 and data[0x100:0x104] == b"SEGA"

def megadrive():
    dest = cache_dir("megadrive")
    if has_payload(dest):
        print(f"[ok]   {dest} (kept)")
        return
    archive = pick_zip("megadrive")
    if not archive:
        raise SystemExit("[miss] megadrive archive")
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir() or info.file_size < 512:
                continue
            with zf.open(info) as handle:
                data = handle.read(0x120)
            if is_genesis(data):
                extract_zip_member(archive, info.filename, dest, "smoke.md")
                return
    raise SystemExit("[miss] megadrive image")

def psx():
    dest = cache_dir("psx")
    for dirpath, _, filenames in os.walk(dest):
        if any(name.lower().endswith(".cue") for name in filenames):
            print(f"[ok]   {dest} (kept)")
            return
    archive = None
    for path in archives("psx"):
        with open(path, "rb") as handle:
            magic = handle.read(6)
        if magic.startswith(b"7z\xbc\xaf\x27\x1c") or zipfile.is_zipfile(path):
            archive = path
            break
    if not archive:
        raise SystemExit("[miss] psx archive")
    if not os.path.isfile(sevenzr):
        raise SystemExit(f"[miss] 7zr not found: {sevenzr}")
    subprocess.check_call([sevenzr, "x", archive, f"-o{dest}", "-y"], stdout=subprocess.DEVNULL)
    cues = []
    for dirpath, _, filenames in os.walk(dest):
        for name in filenames:
            if name.lower().endswith(".cue"):
                cues.append(os.path.join(dirpath, name))
    if not cues:
        raise SystemExit("[miss] psx cue")
    print(f"[ok]   {cues[0]}")

try:
    nes()
    snes()
    megadrive()
    psx()
except SystemExit as exc:
    if exc.code not in (0, None):
        print(exc.code if isinstance(exc.code, str) else "rom extract failed", file=sys.stderr)
        raise
PY
}

library_root() {
  local name="$1"
  local value="$2"
  local -a info
  mapfile -t info < <(resolve_library "$value" "$name")
  printf '%s\n' "${info[1]}"
}

cache_file() {
  local system="$1"
  local root file
  root="$(library_root roms "$RETROBAT_ROMS")/.cache/$system"
  [[ -d "$root" ]] || return 1
  file="$(find "$root" -type f ! -iname '*.bin' -print -quit)"
  if [[ "$system" == "psx" ]]; then
    file="$(find "$root" -type f -iname '*.cue' -print -quit)"
  fi
  [[ -n "$file" ]] || return 1
  printf '%s\n' "$file"
}
