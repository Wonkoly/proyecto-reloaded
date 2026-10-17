"""Decodes the game's obfuscated text files (data/text/<lang>/*.dll) into UTF-8 .txt.

The cipher is the one in scripts ValuesAdjustment6 (per-char substitution) and
SpecialChars (&{x} escapes for accented letters), so we read both from the dump.

Usage: python3 -I decode_text.py <extracted_dir> <game_data_text_dir> <out_dir>
"""
import re, sys
from pathlib import Path

extracted, text_dir, out = map(Path, sys.argv[1:4])
sub = {int(a): int(b) for a, b in re.findall(
    r"argument0=(\d+)\)return\((\d+)\)", (extracted / "scripts/ValuesAdjustment6.gml").read_text())}
escapes = re.findall(r'string_replace_all\(txt,"([^"]*)","([^"]*)"\)',
                     (extracted / "scripts/SpecialChars.gml").read_text())

def decode(line: str) -> str:
    s = "".join(chr(sub.get(ord(c), ord(c))) for c in line)
    for k, v in escapes:
        s = s.replace(k, v)
    return s

count = 0
for f in sorted(text_dir.rglob("*.dll")):
    lines = f.read_bytes().decode("cp1252", errors="replace").split("\r\n")
    dest = out / f.relative_to(text_dir).with_suffix(".txt")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(decode(l) for l in lines), encoding="utf-8")
    count += 1
print(f"decoded {count} files -> {out}")
