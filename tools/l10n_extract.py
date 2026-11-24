#!/usr/bin/env python3
"""Builds Localization/en.json from the compiler's .stringsdata files.

Usage: tools/l10n_extract.py <stringsdata-dir>
Each entry: {"en": text or {plural forms}, "where": "File.swift:line", "line": source line}.
Plural keys and notes come from Localization/notes.json and are kept across runs.
"""
import glob, json, os, sys

src_dir, repo = sys.argv[1], os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
notes_path = os.path.join(repo, "Localization", "notes.json")
notes = json.load(open(notes_path)) if os.path.exists(notes_path) else {}
skip = set(notes.get("_skip", []))
entries = {}
for f in sorted(glob.glob(os.path.join(src_dir, "*.stringsdata"))):
    d = json.load(open(f))
    source = d["source"]
    lines = open(source).read().splitlines()
    for e in d.get("tables", {}).get("Localizable", []):
        key = e["key"]
        if key in skip or key in entries:
            continue
        ln = e["location"]["startingLine"]
        entries[key] = {
            "en": notes.get("_plural", {}).get(key, key),
            "where": f"{os.path.relpath(source, repo)}:{ln}",
            "line": lines[ln - 1].strip()[:160],
        }
        if key in notes.get("_note", {}):
            entries[key]["note"] = notes["_note"][key]
out = os.path.join(repo, "Localization", "en.json")
json.dump(dict(sorted(entries.items(), key=lambda kv: kv[1]["where"])), open(out, "w"), ensure_ascii=False, indent=2)
print(f"wrote {out}: {len(entries)} keys")
