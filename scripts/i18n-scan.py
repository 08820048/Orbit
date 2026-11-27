#!/usr/bin/env python3
"""Finds Chinese string literals in the Swift sources that the compiler does NOT treat as localizable.

Usage: scripts/i18n-scan.py <dir with .stringsdata from `swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc <dir>`>
Prints file:line:col and the literal, so each can be wrapped in String(localized:) or left alone on purpose.
"""
import glob, json, os, re, sys

def han(s): return any('一' <= c <= '鿿' for c in s)

def literals(src):
    """Yield (line, col, start, end, text) for every string literal, handling \\( ... ) interpolation and comments."""
    i, line, col, n = 0, 1, 1, len(src)
    def adv(k=1):
        nonlocal i, line, col
        for _ in range(k):
            if src[i] == '\n': line += 1; col = 1
            else: col += 1
            i += 1
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            while i < n and src[i] != '\n': adv()
        elif src.startswith('/*', i):
            while i < n and not src.startswith('*/', i): adv()
            adv(2)
        elif c == '"':
            if src.startswith('"""', i):   # multi-line: skip
                adv(3)
                while i < n and not src.startswith('"""', i): adv()
                adv(3); continue
            sl, sc, st = line, col, i
            adv()
            depth = 0
            while i < n:
                if src[i] == '\\' and src.startswith('\\(', i):
                    adv(2); depth = 1
                    while i < n and depth:
                        if src[i] == '(': depth += 1
                        elif src[i] == ')': depth -= 1
                        elif src[i] == '"':   # nested literal inside the interpolation
                            adv()
                            while i < n and src[i] != '"':
                                if src[i] == '\\': adv()
                                adv()
                        adv()
                    continue
                if src[i] == '\\': adv(2); continue
                if src[i] == '"': adv(); break
                adv()
            yield sl, sc, st, i, src[st:i]
        else:
            adv()

def main():
    locdir = sys.argv[1]
    auto = set()
    for f in glob.glob(os.path.join(locdir, '*.stringsdata')):
        d = json.load(open(f))
        for items in d.get('tables', {}).values():
            for it in items:
                auto.add((d['source'], it['location']['startingLine'], it['location']['startingColumn']))
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    total = 0
    for path in sorted(glob.glob(root + '/Sources/**/*.swift', recursive=True)):
        src = open(path, encoding='utf-8').read()
        for line, col, st, en, text in literals(src):
            if not han(text): continue
            if (path, line, col) in auto: continue
            total += 1
            print(f"{os.path.relpath(path, root)}:{line}:{col}: {text}")
    print(f"-- {total} plain literals", file=sys.stderr)

main()
