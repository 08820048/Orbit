#!/usr/bin/env python3
"""Checks that every Chinese UI string the compiler finds has an English translation.

  swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc /tmp/loc   (touch the sources first)
  scripts/i18n-check.py /tmp/loc

Prints keys missing from Packaging/Localization/en.lproj/Localizable.strings and entries that no longer exist in the code.
"""
import glob, json, os, re, sys

def han(s): return any('一' <= c <= '鿿' for c in s)

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
found = {}
for f in glob.glob(os.path.join(sys.argv[1], '*.stringsdata')):
    d = json.load(open(f))
    for items in d.get('tables', {}).values():
        for it in items:
            if han(it['key']): found[it['key']] = os.path.basename(d['source'])

text = open(os.path.join(root, 'Packaging/Localization/en.lproj/Localizable.strings'), encoding='utf-8').read()
have = {}
for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M):
    unesc = lambda s: s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
    have[unesc(m.group(1))] = unesc(m.group(2))

missing = [k for k in found if k not in have or not have[k].strip()]
unused = [k for k in have if k not in found]
for k in missing: print(f"MISSING  {found[k]}: {k!r}")
for k in unused: print(f"UNUSED   {k!r}")
print(f"-- {len(found)} keys in code, {len(have)} translated, {len(missing)} missing, {len(unused)} unused")
sys.exit(1 if missing else 0)
