#!/usr/bin/env python3
"""Summarise the Qualcomm PEP power recipes in a decompiled DSDT.

Usage: iasl -d dsdt.dat; python3 -I tools/power/pep-dump.py dsdt.dsl > pep-summary.txt

Every top-level ASL Package that starts with "DEVICE" is one device's recipe:
COMPONENTs with FSTATEs, DSTATEs and PSTATEs, each a list of actions
(PMICVREGVOTE, FOOTSWITCH, CLOCK, BUSARB, DELAY, TLMMPORT, ...). This prints
one line per action, in order, with voltages in volts.
"""
import re
import sys

TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|(Package\s*\([^)]*\))|([{}])'
                   r'|\b(0x[0-9A-Fa-f]+|\d+|Zero|One|Ones)\b(?![.\w])|(,)')
CONST = {"Zero": 0, "One": 1, "Ones": 0xFFFFFFFFFFFFFFFF}


def tokens(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    for m in TOKEN.finditer(text):
        s, pkg, brace, num, _ = m.groups()
        if s is not None:
            yield ("str", s.replace("\\\\", "\\"))
        elif pkg:
            yield ("pkg", None)
        elif brace:
            yield (brace, None)
        elif num:
            yield ("num", CONST[num] if num in CONST else int(num, 0))


def parse(toks, i):
    """toks[i] is a 'pkg' token; return (list, next index)."""
    assert toks[i][0] == "pkg" and toks[i + 1][0] == "{"
    i += 2
    out = []
    while toks[i][0] != "}":
        kind, val = toks[i]
        if kind == "pkg":
            val, i = parse(toks, i)
            out.append(val)
            continue
        if kind in ("str", "num"):
            out.append(val)
        i += 1
    return out, i + 1


def fmt_action(a):
    if not (isinstance(a, list) and a and isinstance(a[0], str)):
        return repr(a)
    kind, args = a[0], a[1:]
    if len(args) == 1 and isinstance(args[0], list):
        args = args[0]
    if kind == "PMICVREGVOTE" and len(args) >= 4 and isinstance(args[0], str):
        name = args[0].replace("PPP_RESOURCE_ID_", "")
        if len(args) == 6:  # name, type, uV, enable, mode, ?
            _, typ, uv, en, mode, extra = args
            return f"vreg   {name:<10} {'ON ' if en else 'OFF'} {uv/1e6:.3f} V mode {mode} type {typ} {extra}"
        return f"vreg   {name:<10} {args[1:]}"
    if kind == "PMICVREGVOTE" and len(args) == 3:
        return f"vreg   {args[0].replace('PPP_RESOURCE_ID_', ''):<10} {args[1:]}"
    if kind == "FOOTSWITCH":
        return f"gdsc   {args[0]} {'ON' if args[1] == 1 else 'OFF' if args[1] == 2 else args[1]}"
    if kind == "CLOCK":
        act = {1: "ON", 2: "OFF", 3: "SET", 4: "SET", 6: "CFG", 8: "FREQ", 9: "FREQ"}.get(args[1], args[1])
        rest = [x for x in args[2:] if x] if len(args) > 2 else []
        return f"clock  {args[0]} {act}{' ' + str(rest) if rest else ''}"
    if kind == "BUSARB":
        return f"bus    {args}"
    return f"{kind.lower():<6} {args}"


def show(node, depth=0):
    pad = "  " * depth
    if not (isinstance(node, list) and node and isinstance(node[0], str)):
        print(pad + repr(node))
        return
    kind = node[0]
    if kind in ("COMPONENT",):
        print(f"{pad}COMPONENT {node[1]}")
        for c in node[2:]:
            show(c, depth + 1)
    elif kind in ("FSTATE", "DSTATE", "PSTATE", "PRELOAD_PSTATE", "ABANDON_DSTATE", "PSTATE_SET",
                  "DISCOVERABLE", "WAKE", "INIT"):
        head = [x for x in node[1:] if not isinstance(x, list)]
        acts = [x for x in node[1:] if isinstance(x, list)]
        print(f"{pad}{kind} {' '.join(map(str, head))}" + ("" if acts else "  (no actions)"))
        for a in acts:
            if a and a[0] in ("PSTATE", "PSTATE_SET", "FSTATE", "DSTATE"):
                show(a, depth + 1)
            else:
                print(f"{pad}  {fmt_action(a)}")
    else:
        print(pad + fmt_action(node))


def main():
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    toks = list(tokens(text))
    seen = 0
    i = 0
    while i < len(toks) - 2:
        if toks[i][0] == "pkg" and toks[i + 1][0] == "{" and toks[i + 2] == ("str", "DEVICE"):
            pkg, j = parse(toks, i)
            seen += 1
            print(f"\n===== {pkg[1]}")
            for part in pkg[2:]:
                show(part, 1)
            i = j
        else:
            i += 1
    print(f"\n# {seen} device recipes", file=sys.stderr)


if __name__ == "__main__":
    main()
