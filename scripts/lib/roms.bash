#!/usr/bin/env bash
# Unpack already-present images from the ROM library.
# .cache keeps one smoke image per system for play and test.
# .unpacked receives every playable image for the RetroArch menu.
# This does not download ROM files.

cmd_roms() {
  local rom_root
  rom_root="$(library_root roms "$RETROBAT_ROMS")"
  [[ -d "$rom_root" ]] || die "ROM library missing: $rom_root"
  python - "$rom_root" "$(win_path "$SEVENZR")" <<'PY'
import os, sys, zipfile, shutil, subprocess
root, sevenzr = sys.argv[1], sys.argv[2]
SKIP_DIRS = (".cache", ".unpacked")

def under_skipped(path):
    abspath = os.path.abspath(path)
    for name in SKIP_DIRS:
        blocked = os.path.abspath(os.path.join(root, name))
        if abspath == blocked or abspath.startswith(blocked + os.sep):
            return True
    return False

def archives(system):
    base = os.path.join(root, system)
    if not os.path.isdir(base):
        return
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if under_skipped(path):
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

def decode_bytes(data):
    for encoding in ("utf-8", "mbcs", "gbk"):
        try:
            return data.decode(encoding)
        except (UnicodeDecodeError, LookupError):
            continue
    return data.decode("utf-8", errors="replace")

def win_path(path):
    proc = subprocess.run(["cygpath", "-w", path], check=True, capture_output=True)
    return decode_bytes(proc.stdout).strip()

def archive_kind(path):
    with open(path, "rb") as handle:
        magic = handle.read(6)
    if magic.startswith(b"7z\xbc\xaf\x27\x1c"):
        return "7z"
    if zipfile.is_zipfile(path):
        return "zip"
    return None

def archive_dirname(path):
    return os.path.splitext(os.path.basename(path))[0]

def unpacked_dir(system, archive):
    dest = os.path.join(root, ".unpacked", system, archive_dirname(archive))
    os.makedirs(dest, exist_ok=True)
    return dest

def safe_dest(dest_dir, member, flatten):
    parts = []
    for part in member.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            return None
        parts.append(part)
    if not parts:
        return None
    if flatten:
        parts = [parts[-1]]
    return os.path.join(dest_dir, *parts)

def same_file(path, size):
    return os.path.isfile(path) and os.path.getsize(path) == size

def kept(path):
    print(f"[ok]   {path} (kept)")

def write_new(path, reader):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        reader(handle)
    print(f"[ok]   {path}")

def list_7z(archive):
    proc = subprocess.run([sevenzr, "l", "-slt", archive], capture_output=True)
    if proc.returncode != 0:
        message = decode_bytes(proc.stderr).strip() or "7zr failed"
        raise SystemExit(message)
    blocks = []
    current = None
    for line in decode_bytes(proc.stdout).splitlines():
        if line.startswith("Path = "):
            if current:
                blocks.append(current)
            current = {"Path": line[len("Path = "):]}
        elif current is not None and " = " in line:
            key, value = line.split(" = ", 1)
            current[key] = value
    if current:
        blocks.append(current)
    files = []
    for block in blocks[1:]:
        if block.get("Folder") == "+":
            continue
        if "Size" not in block:
            continue
        files.append((block["Path"], int(block["Size"])))
    return files

def extract_7z_member(archive, member, dest_path):
    temp_dir = dest_path + ".tmp"
    if os.path.isdir(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)
    subprocess.check_call(
        [sevenzr, "e", archive, f"-o{win_path(temp_dir)}", "-y", member],
        stdout=subprocess.DEVNULL,
    )
    extracted = None
    for dirpath, _, filenames in os.walk(temp_dir):
        if filenames:
            extracted = os.path.join(dirpath, filenames[0])
            break
    if not extracted:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise SystemExit(f"[miss] 7zr member {member}")
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    os.replace(extracted, dest_path)
    shutil.rmtree(temp_dir, ignore_errors=True)

def require_7zr():
    if not os.path.isfile(sevenzr):
        raise SystemExit(f"[miss] 7zr not found: {sevenzr}")

def unpack_zip_members(archive, dest, accept, flatten):
    wrote = 0
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            out = safe_dest(dest, info.filename, flatten)
            if not out:
                continue
            with zf.open(info) as src:
                prefix = src.read(0x120)
                if not accept(info.filename, prefix, info.file_size):
                    continue
                if same_file(out, info.file_size):
                    kept(out)
                    wrote += 1
                    continue
                def reader(handle, prefix=prefix, src=src):
                    handle.write(prefix)
                    shutil.copyfileobj(src, handle)
                write_new(out, reader)
                wrote += 1
    return wrote

def accept_nes(name, prefix, size):
    return prefix[:4] == b"NES\x1a"

def accept_snes(name, prefix, size):
    lower = name.lower()
    return lower.endswith(".smc") or lower.endswith(".sfc")

def accept_megadrive(name, prefix, size):
    return size >= 512 and is_genesis(prefix)

def accept_psx(name, prefix, size):
    return True

def unpack_7z_filtered(archive, dest, accept, flatten):
    require_7zr()
    wrote = 0
    for member, size in list_7z(archive):
        out = safe_dest(dest, member, flatten)
        if not out:
            continue
        if same_file(out, size):
            with open(out, "rb") as handle:
                prefix = handle.read(0x120)
            if accept(member, prefix, size):
                kept(out)
                wrote += 1
                continue
        extract_7z_member(archive, member, out)
        with open(out, "rb") as handle:
            prefix = handle.read(0x120)
        if not accept(member, prefix, os.path.getsize(out)):
            os.remove(out)
            continue
        print(f"[ok]   {out}")
        wrote += 1
    return wrote

def unpack_filtered(system, archive, kind, accept):
    dest = unpacked_dir(system, archive)
    if kind == "zip":
        wrote = unpack_zip_members(archive, dest, accept, True)
    else:
        wrote = unpack_7z_filtered(archive, dest, accept, True)
    if wrote == 0:
        print(f"[miss] {system} playable image in {archive}", file=sys.stderr)

def cues_under(dest):
    found = []
    for dirpath, _, filenames in os.walk(dest):
        for name in filenames:
            if name.lower().endswith(".cue"):
                found.append(os.path.join(dirpath, name))
    return found

def unpack_psx(archive, kind):
    dest = unpacked_dir("psx", archive)
    if kind == "zip":
        wrote = unpack_zip_members(archive, dest, accept_psx, False)
        if wrote == 0 or not cues_under(dest):
            print(f"[miss] psx cue in {archive}", file=sys.stderr)
        return
    require_7zr()
    members = list_7z(archive)
    pending = False
    for member, size in members:
        out = safe_dest(dest, member, False)
        if not out:
            continue
        if not same_file(out, size):
            pending = True
            break
    if members and not pending:
        cues = cues_under(dest)
        if not cues:
            print(f"[miss] psx cue in {archive}", file=sys.stderr)
            return
        for cue in cues:
            kept(cue)
        return
    subprocess.check_call(
        [sevenzr, "x", archive, f"-o{win_path(dest)}", "-y"],
        stdout=subprocess.DEVNULL,
    )
    cues = cues_under(dest)
    if not cues:
        print(f"[miss] psx cue in {archive}", file=sys.stderr)
        return
    for cue in cues:
        print(f"[ok]   {cue}")

def unpack_all():
    accept_for = {
        "nes": accept_nes,
        "snes": accept_snes,
        "megadrive": accept_megadrive,
    }
    for system in ("nes", "snes", "megadrive", "psx"):
        found = False
        for path in archives(system):
            kind = archive_kind(path)
            if not kind:
                continue
            found = True
            if system == "psx":
                unpack_psx(path, kind)
            else:
                unpack_filtered(system, path, kind, accept_for[system])
        if not found:
            print(f"[miss] {system} archive", file=sys.stderr)

try:
    nes()
    snes()
    megadrive()
    psx()
    unpack_all()
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
