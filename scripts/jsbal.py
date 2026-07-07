#!/usr/bin/env python3
# Bracket-balance checker for LuCI JS views (no JS runtime on the dev box).
# String/comment/regex-aware; catches the paren/bracket imbalances that break a
# LuCI page at parse time. Not a full JS parser. Usage: python3 scripts/jsbal.py <file...>
import sys


def check(path):
    s = open(path, encoding='utf-8').read()
    i, n = 0, len(s)
    stack = []
    line = 1
    prev = ''  # last significant char (regex-vs-divide heuristic)
    pairs = {')': '(', ']': '[', '}': '{'}
    while i < n:
        c = s[i]
        if c == '\n':
            line += 1; i += 1; continue
        if c in ' \t\r':
            i += 1; continue
        if c == '/' and i + 1 < n and s[i + 1] == '/':
            while i < n and s[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '*':
            i += 2
            while i + 1 < n and not (s[i] == '*' and s[i + 1] == '/'):
                if s[i] == '\n':
                    line += 1
                i += 1
            i += 2; continue
        if c in "'\"`":
            q = c; i += 1
            while i < n:
                if s[i] == '\\':
                    i += 2; continue
                if s[i] == '\n':
                    line += 1
                if s[i] == q:
                    break
                i += 1
            i += 1; prev = q; continue
        if c == '/' and prev in "(,=:[!&|?{;":
            j = i + 1; ok = True; inclass = False
            while j < n:
                if s[j] == '\\':
                    j += 2; continue
                if s[j] == '\n':
                    ok = False; break
                if s[j] == '[':
                    inclass = True
                elif s[j] == ']':
                    inclass = False
                elif s[j] == '/' and not inclass:
                    break
                j += 1
            if ok and j < n:
                i = j + 1; prev = '/'; continue
        if c in '([{':
            stack.append((c, line)); prev = c; i += 1; continue
        if c in ')]}':
            if not stack:
                print(f"{path}:{line}: unmatched closing '{c}'"); return False
            op, ol = stack.pop()
            if op != pairs[c]:
                print(f"{path}:{line}: '{c}' closes '{op}' opened at line {ol}"); return False
            prev = c; i += 1; continue
        prev = c; i += 1
    if stack:
        op, ol = stack[-1]
        print(f"{path}: unclosed '{op}' opened at line {ol}"); return False
    print(f"{path}: brackets balanced OK"); return True


if __name__ == '__main__':
    rc = 0
    for p in sys.argv[1:]:
        if not check(p):
            rc = 1
    sys.exit(rc)
