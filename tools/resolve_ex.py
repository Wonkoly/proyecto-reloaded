"""Rewrites obfuscated `ex(<script id>, args...)` calls into `ScriptName(args...)`.

Usage: python3 -I resolve_ex.py <extracted_dir>
Edits the .gml files in place; safe to run more than once.
"""
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
scripts = json.loads((root / "index.json").read_text())["scripts"]
call = re.compile(r"\bex\(\s*(\d+)\s*([,)])")

def repl(m):
    name = scripts[int(m.group(1))] if int(m.group(1)) < len(scripts) else None
    if not name:
        return m.group(0)
    return f"{name}(" if m.group(2) == "," else f"{name}()"

total = unresolved = 0
for f in list((root / "scripts").glob("*.gml")) + list((root / "objects").glob("*.gml")):
    src = f.read_text(encoding="utf-8")
    new, n = call.subn(repl, src)
    if n:
        total += n
        f.write_text(new, encoding="utf-8")
    unresolved += len(call.findall(new))

# Room and instance creation code lives inside the room JSONs.
for f in (root / "rooms").glob("*.json"):
    room = json.loads(f.read_text(encoding="utf-8"))
    changed = False
    for holder in [room] + room["instances"]:
        c = holder.get("creation_code") or ""
        new, n = call.subn(repl, c)
        if n:
            holder["creation_code"] = new
            total += n
            changed = True
    if changed:
        f.write_text(json.dumps(room, indent=2, ensure_ascii=False), encoding="utf-8")

print(f"resolved {total} ex() calls, {unresolved} left unresolved in gml")
