"""Fetch only Windows x64 ZIP entries from Godot's official redirect destination.

Range downloads avoid fetching templates for other platforms. Validate ZIP CRC and
uncompressed length, and record per-binary SHA-256; this does not claim to verify
the published hash of the entire 1.28 GB archive.
"""
import hashlib
import json
from pathlib import Path
import struct
import time
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parent.parent
URL = "https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
TOTAL = 1281349702
CACHE = ROOT / ".tools/downloads"
DEST = ROOT / ".tools/godot/editor_data/export_templates/4.7.2.stable"
CACHE.mkdir(parents=True, exist_ok=True)
DEST.mkdir(parents=True, exist_ok=True)


def fetch(start, length):
    for attempt in range(4):
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{start + length - 1}"})
            with urllib.request.urlopen(req, timeout=45) as response:
                if response.status != 206 or response.headers.get("Content-Range", "").split(" ")[-1].split("-")[0] != str(start):
                    raise ValueError("Server did not honor the exact ZIP range")
                body = response.read()
                if len(body) != length:
                    raise ValueError("Truncated ZIP range")
                return body
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1)


tail = (CACHE / "template-tail.bin").read_bytes() if (CACHE / "template-tail.bin").exists() else fetch(TOTAL - 65536, 65536)
end = struct.unpack_from("<4s4H2IH", tail, tail.rfind(b"PK\x05\x06"))
index = end[6] - (TOTAL - len(tail))
entries = []
while tail[index:index + 4] == b"PK\x01\x02":
    header = struct.unpack_from("<4s6H3I5H2I", tail, index)
    name = tail[index + 46:index + 46 + header[10]].decode()
    if "windows_" in name and "x86_64" in name:
        local = fetch(header[16], 256)
        fields = struct.unpack_from("<4s5H3I2H", local)
        offset = header[16] + 30 + fields[9] + fields[10]
        parts = []
        for part in range(0, header[8], 2 * 1024 * 1024):
            length = min(2 * 1024 * 1024, header[8] - part)
            path = CACHE / (Path(name).name + f".{part}.chunk")
            data = path.read_bytes() if path.exists() and path.stat().st_size == length else fetch(offset + part, length)
            path.write_bytes(data)
            parts.append(data)
            print(f"{name}: {part + length}/{header[8]}", flush=True)
        data = zlib.decompress(b"".join(parts), -15)
        assert len(data) == header[9] and zlib.crc32(data) == header[7], "ZIP entry integrity check failed"
        (DEST / Path(name).name).write_bytes(data)
        entries.append({"name": name, "size": len(data), "zip_crc_verified": True, "sha256": hashlib.sha256(data).hexdigest()})
    index += 46 + header[10] + header[11] + header[12]
(DEST / "version.txt").write_text("4.7.2.stable", encoding="utf-8")
(ROOT / "docs/evidence/p8-templates.json").write_text(json.dumps({"source": URL, "whole_archive_sha256_verified": False, "entries": entries}, indent=2), encoding="utf-8")
