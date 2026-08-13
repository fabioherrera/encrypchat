#!/usr/bin/env python3
"""Drop build-machine paths out of the RUNPATH of shipped ELF files.

Flutter's CMake leaves the build tree baked into the plugin libraries: every one of them
carries an absolute path to `apps/client/linux/flutter/ephemeral` on whichever machine
produced the build. Two reasons that cannot ship.

It leaks. A tarball or an RPM would tell anyone who opens it the builder's username and
directory layout, and this is a product whose whole claim is about not leaking things.

And it is a loader instruction, not a comment. On the build machine those directories do
exist, so an installed copy prefers the libraries sitting in the build tree over the ones
it was shipped with — which is exactly the machine where the packages get tested, and the
one place the difference would go unnoticed.

`patchelf --set-rpath` is the usual tool for this. It is not in Fedora's default install, so
this does the same edit directly, which is possible because the replacement is always
shorter: absolute paths give way to `$ORIGIN`, and a string can be shortened in place.
"""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

DT_NULL, DT_STRTAB, DT_RPATH, DT_RUNPATH = 0, 5, 15, 29
PT_LOAD, PT_DYNAMIC = 1, 2


class NotAnElf(Exception):
    pass


def _read_headers(data: bytes):
    if data[:4] != b"\x7fELF":
        raise NotAnElf("not an ELF file")
    if data[4] != 2 or data[5] != 1:
        raise NotAnElf("only 64-bit little-endian is handled")

    e_phoff, = struct.unpack_from("<Q", data, 32)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 54)

    segments = []
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from("<I", data, base)
        p_offset, p_vaddr = struct.unpack_from("<QQ", data, base + 8)
        p_filesz, = struct.unpack_from("<Q", data, base + 32)
        segments.append((p_type, p_offset, p_vaddr, p_filesz))
    return segments


def _vaddr_to_offset(segments, vaddr: int) -> int:
    for p_type, p_offset, p_vaddr, p_filesz in segments:
        if p_type == PT_LOAD and p_vaddr <= vaddr < p_vaddr + p_filesz:
            return p_offset + (vaddr - p_vaddr)
    raise NotAnElf(f"address {vaddr:#x} is in no loadable segment")


def _find_runpath(data: bytes):
    """Return (file offset of the string, current value) or None."""
    segments = _read_headers(data)
    dynamic = next((s for s in segments if s[0] == PT_DYNAMIC), None)
    if dynamic is None:
        return None
    _, dyn_off, _, dyn_size = dynamic

    strtab_vaddr = None
    entry_val = None
    for pos in range(dyn_off, dyn_off + dyn_size, 16):
        tag, val = struct.unpack_from("<qQ", data, pos)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            strtab_vaddr = val
        elif tag in (DT_RPATH, DT_RUNPATH):
            entry_val = val

    if entry_val is None or strtab_vaddr is None:
        return None

    start = _vaddr_to_offset(segments, strtab_vaddr) + entry_val
    end = data.index(b"\0", start)
    return start, data[start:end].decode("utf-8", "surrogateescape")


def _rewrite(current: str, strip_prefix: str) -> str | None:
    """Drop the entries that point into the build tree. None if nothing to do.

    Only those. `libdartjni.so` asks for `/usr/lib/jvm/jre/lib/server`, which is a real
    place on the target machine and none of our business; removing it would be fixing a
    problem nobody has.
    """
    kept = [p for p in current.split(":") if p and not p.startswith(strip_prefix)]
    # A library left with nothing still has to find its siblings, which is what it was
    # using the build tree for.
    new = ":".join(dict.fromkeys(kept)) or "$ORIGIN"
    return None if new == current else new


def _describe(path: Path) -> str:
    """readelf's view of everything that lives in the string table we are editing."""
    out = []
    for args in (["-dW"], ["--dyn-syms", "-W"]):
        proc = subprocess.run(
            ["readelf", *args, str(path)], capture_output=True, text=True, check=True
        )
        out.append(
            "\n".join(
                line
                for line in proc.stdout.splitlines()
                if "RUNPATH" not in line and "RPATH" not in line
            )
        )
    return "\n".join(out)


def fix(path: Path, strip_prefix: str) -> str | None:
    """Patch one file. Returns the new RUNPATH, or None if it needed no change."""
    data = bytearray(path.read_bytes())
    found = _find_runpath(bytes(data))
    if found is None:
        return None
    start, current = found
    new = _rewrite(current, strip_prefix)
    if new is None:
        return None

    encoded = new.encode()
    if len(encoded) > len(current):
        raise NotAnElf(f"replacement is longer than the original: {new!r}")

    before = _describe(path)
    backup = path.with_suffix(path.suffix + ".runpath-backup")
    shutil.copy2(path, backup)

    # Blank the tail as well as writing the shorter string: leaving the old bytes behind
    # would keep the build path readable with `strings`, which is half of why we are here.
    # String tables do share suffixes, though, so the edit is only kept if readelf still
    # reports the same symbols and dependencies afterwards.
    data[start : start + len(current) + 1] = encoded + b"\0" * (len(current) - len(encoded) + 1)
    path.write_bytes(data)

    try:
        if _describe(path) != before:
            raise NotAnElf("blanking the tail disturbed another string")
    except (subprocess.CalledProcessError, NotAnElf):
        # Fall back to the conservative edit: write the string, leave the rest alone.
        data = bytearray(backup.read_bytes())
        data[start : start + len(encoded) + 1] = encoded + b"\0"
        path.write_bytes(data)
        if _describe(path) != before:
            shutil.copy2(backup, path)
            backup.unlink()
            raise NotAnElf("could not rewrite RUNPATH without changing something else")

    backup.unlink()
    return new


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: fix-runpath.py <build-root> <file-or-directory>...", file=sys.stderr)
        return 2

    strip_prefix = str(Path(argv[1]).resolve())
    targets: list[Path] = []
    for arg in argv[2:]:
        path = Path(arg)
        if path.is_dir():
            targets.extend(sorted(p for p in path.rglob("*") if p.is_file()))
        else:
            targets.append(path)

    changed = 0
    for target in targets:
        try:
            new = fix(target, strip_prefix)
        except NotAnElf as exc:
            if "not an ELF" in str(exc) or "64-bit" in str(exc):
                continue
            print(f"error: {target}: {exc}", file=sys.stderr)
            return 1
        if new is not None:
            print(f"runpath: {target.name} → {new}")
            changed += 1

    print(f"runpath: {changed} file(s) rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
