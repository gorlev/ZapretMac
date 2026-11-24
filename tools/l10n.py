#!/usr/bin/env python3
"""Checks the translations and writes them into the app bundle.

  tools/l10n.py check [lang ...]      validate Localization/<lang>.json against en.json
  tools/l10n.py build <Resources dir> check every language, then write <lang>.lproj/
                                      Localizable.strings and Localizable.stringsdict

Translation files map every key of en.json to a string, or, for plural keys,
to an object of CLDR categories. Placeholders (%@, %lld) must match the
English ones in kind and number; positional forms (%1$@, %2$lld) may reorder them.
"""
import json, os, re, sys
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(REPO, "Localization")
LANGS = ["tr", "de", "es", "it", "fr", "pt-BR", "ru"]
PLURALS = {"ru": ["one", "few", "many", "other"]}
DEFAULT_PLURALS = ["one", "other"]
SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d)")


def specs(text):
    return Counter("@" if m.group(2) == "@" else "lld" for m in SPEC.finditer(text))


def load(name):
    with open(os.path.join(LOC, f"{name}.json"), encoding="utf-8") as f:
        return json.load(f)


def english():
    return {k: v["en"] for k, v in load("en").items()}


def check(lang, en):
    errors = []
    try:
        tr = load(lang)
    except FileNotFoundError:
        return [f"{lang}: Localization/{lang}.json is missing"]
    except json.JSONDecodeError as e:
        return [f"{lang}: not valid JSON: {e}"]
    missing, extra = set(en) - set(tr), set(tr) - set(en)
    errors += [f"{lang}: missing key {k!r}" for k in sorted(missing)]
    errors += [f"{lang}: unknown key {k!r}" for k in sorted(extra)]
    need = PLURALS.get(lang, DEFAULT_PLURALS)
    for key in sorted(set(en) & set(tr)):
        src, val = en[key], tr[key]
        if isinstance(src, dict):
            if not isinstance(val, dict):
                errors.append(f"{lang}: {key!r} must be a plural object with {need}")
                continue
            for cat in need:
                if not val.get(cat, "").strip():
                    errors.append(f"{lang}: {key!r} needs plural form {cat!r}")
            # Every form may drop the number, but no form may add a placeholder
            # English does not have, and %@ must survive in every form.
            allowed = specs(src["other"])
            for cat, text in val.items():
                got = specs(text)
                if any(got[k] > allowed[k] for k in got) or got["@"] != allowed["@"]:
                    errors.append(f"{lang}: {key!r} [{cat}] placeholders {dict(got)} vs English {dict(allowed)}")
        else:
            if not isinstance(val, str) or not val.strip():
                errors.append(f"{lang}: {key!r} is empty or not a string")
            elif specs(val) != specs(src):
                errors.append(f"{lang}: {key!r} placeholders {dict(specs(val))} vs English {dict(specs(src))}")
            else:
                # A value far longer or shorter than its English is usually a
                # value written under the wrong key (a name where a sentence
                # belongs). Catches a block of values shifted by one.
                ratio = len(val) / max(len(src), 1)
                if (ratio > 3 and len(val) > 30) or (ratio < 0.3 and len(src) > 30):
                    errors.append(f"{lang}: {key!r} looks like the value of another key: {val[:60]!r}")
    return errors


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def xml(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def positional(form, key):
    """In a plural form, the count is argument 1 and a %@ is argument 2."""
    if "%@" in key and "%lld" in key:
        form = re.sub(r"%(?!\d+\$)lld", "%1$lld", form)
        form = re.sub(r"%(?!\d+\$)@", "%2$@", form)
    return form


def write(lang, table, out):
    folder = os.path.join(out, f"{lang}.lproj")
    os.makedirs(folder, exist_ok=True)
    flat = {k: v for k, v in table.items() if isinstance(v, str)}
    plural = {k: v for k, v in table.items() if isinstance(v, dict)}
    with open(os.path.join(folder, "Localizable.strings"), "w", encoding="utf-8") as f:
        for k in sorted(flat):
            f.write(f'"{esc(k)}" = "{esc(flat[k])}";\n')
    entries = []
    for k in sorted(plural):
        lead = "%1$#@n@" if ("%@" in k and "%lld" in k) else "%#@n@"
        forms = "".join(f"<key>{c}</key><string>{xml(positional(t, k))}</string>"
                        for c, t in plural[k].items())
        entries.append(f"<key>{xml(k)}</key><dict><key>NSStringLocalizedFormatKey</key><string>{lead}</string>"
                       f"<key>n</key><dict><key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>"
                       f"<key>NSStringFormatValueTypeKey</key><string>lld</string>{forms}</dict></dict>")
    with open(os.path.join(folder, "Localizable.stringsdict"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>'
                + "".join(entries) + "</dict></plist>\n")


def main():
    en = english()
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        langs = sys.argv[2:] or LANGS
        errors = [e for lang in langs for e in check(lang, en)]
        print("\n".join(errors) if errors else f"PASS l10n: {', '.join(langs)} match en.json ({len(en)} keys)")
        sys.exit(1 if errors else 0)
    if len(sys.argv) == 3 and sys.argv[1] == "build":
        present = [l for l in LANGS if os.path.exists(os.path.join(LOC, f"{l}.json"))]
        errors = [e for lang in present for e in check(lang, en)]
        if errors:
            print("\n".join(errors))
            sys.exit(1)
        out = sys.argv[2]
        write("en", {k: v for k, v in en.items() if isinstance(v, dict)}, out)
        for lang in present:
            write(lang, load(lang), out)
        print(f"wrote localizations: en {' '.join(present)}")
        return
    print(__doc__)
    sys.exit(2)


main()
