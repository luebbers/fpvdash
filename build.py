#!/usr/bin/env python3
"""Build dist/FPVDash-<version>.zip from src/, ready to unzip onto an SD card's root.

    build.py [--force]

The version comes from VERSION in src/WIDGETS/FPVDash/main.lua. A released zip is never
rebuilt unless --force is given; bump VERSION (and CHANGELOG.md) for a new release. Entries
carry the build time: EdgeTX keeps running a compiled .luac that is newer than its .lua.
"""
import hashlib
import re
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"


def main():
    main_lua = (SRC / "WIDGETS/FPVDash/main.lua").read_text()
    version = re.search(r'^local VERSION = "([^"]+)"', main_lua, re.M).group(1)
    out = HERE / "dist" / f"FPVDash-{version}.zip"
    if out.exists() and "--force" not in sys.argv:
        sys.exit(f"{out.relative_to(HERE)} already exists. Bump VERSION in main.lua for a new release.")

    files = sorted(p for p in SRC.rglob("*")
                   if p.is_file() and not p.name.startswith(".") and p.suffix != ".luac")
    stamp = time.localtime()[:6]
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w") as z:
        for p in files:
            info = zipfile.ZipInfo(p.relative_to(SRC).as_posix(), date_time=stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, p.read_bytes())
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"{out.relative_to(HERE)}: {len(files)} files, {out.stat().st_size} bytes, sha256 {digest}")


if __name__ == "__main__":
    main()
