#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare two device tree blobs by content, not by encoding.

phandle numbers depend on how and from which source order a DTB was compiled
(dtc -@ gives every labelled node one), so two DTBs with the same nodes and
properties can differ in every reference. This reads both blobs (no dtc
needed), drops __symbols__ and the phandle properties, and prints references
as &{/path/of/that/node}: in phandle lists (*-supply, pinctrl-N, ...) and in
specifier properties (gpios, clocks, ...: the reference, then the number of
argument cells the provider declares in #...-cells). Everything else stays
numeric.
Nodes and properties are listed sorted, one per line, and diffed.

    tools/kernel/dtb-compare.py a.dtb b.dtb     # exit 0 if equal

A reference in a property not covered above stays a number, so it can show
up as a difference when the numbering differs; it is visible as such.
"""
import difflib
import struct
import sys

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def parse(path):
    data = open(path, "rb").read()
    magic, _size, off_struct, off_strings = struct.unpack_from(">IIII", data, 0)
    if magic != 0xD00DFEED:
        sys.exit(f"{path}: not a DTB")
    nodes, stack, pos = {}, [], off_struct
    while True:
        (tok,) = struct.unpack_from(">I", data, pos)
        pos += 4
        if tok == FDT_BEGIN_NODE:
            end = data.index(b"\0", pos)
            name = data[pos:end].decode()
            pos = (end + 4) & ~3
            stack.append(name)
            path = "/" + "/".join(stack[1:])
            nodes[path] = {}
        elif tok == FDT_END_NODE:
            stack.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", data, pos)
            pos += 8
            value = data[pos:pos + length]
            pos = (pos + length + 3) & ~3
            pname = data[off_strings + nameoff:data.index(b"\0", off_strings + nameoff)].decode()
            nodes["/" + "/".join(stack[1:])][pname] = value
        elif tok == FDT_NOP:
            continue
        elif tok == FDT_END:
            break
        else:
            sys.exit(f"{path}: bad token {tok} at {pos - 4}")
    return nodes


def is_strings(v):
    if not v or v[-1] != 0:
        return False
    parts = v[:-1].split(b"\0")
    return all(p and all(32 <= c < 127 for c in p) for p in parts)


# Properties of the form <&provider arg...>..., with the number of argument
# cells given by the provider's #...-cells property.
SPECIFIERS = {
    "gpios": "#gpio-cells", "gpio": "#gpio-cells", "clocks": "#clock-cells",
    "assigned-clocks": "#clock-cells", "assigned-clock-parents": "#clock-cells",
    "interrupts-extended": "#interrupt-cells", "power-domains": "#power-domain-cells",
    "interconnects": "#interconnect-cells", "phys": "#phy-cells", "resets": "#reset-cells",
    "dmas": "#dma-cells", "iommus": "#iommu-cells", "mboxes": "#mbox-cells",
    "sound-dai": "#sound-dai-cells", "thermal-sensors": "#thermal-sensor-cells",
    "pwms": "#pwm-cells", "io-channels": "#io-channel-cells", "cooling-device": "#cooling-cells",
    "nvmem-cells": "#nvmem-cell-cells", "hwlocks": "#hwlock-cells",
    "qcom,smem-states": "#qcom,smem-state-cells", "msi-map": None,
}
# Properties that are lists of plain references.
PHANDLE_LISTS = {"interrupt-parent", "remote-endpoint", "memory-region", "operating-points-v2",
                 "cpu", "cpu-idle-states", "domain-idle-states", "required-opps", "leds",
                 "msi-parent", "trip", "phy-handle", "sram", "qcom,ice", "qcom,rpm-msg-ram",
                 "qcom,rx-device", "qcom,tx-device"}
# Specifiers with a fixed number of argument cells.
FIXED = {"gpio-ranges": 3}


def cells_of(v):
    return list(struct.unpack(">%dI" % (len(v) // 4), v))


def render(nodes):
    phandles = {}
    for path, props in nodes.items():
        for key in ("phandle", "linux,phandle"):
            if key in props and len(props[key]) == 4:
                phandles[struct.unpack(">I", props[key])[0]] = path

    def ref(c):
        return f"&{{{phandles[c]}}}" if c in phandles else f"0x{c:x}"

    def fmt(name, v):
        cells = cells_of(v)
        kind = SPECIFIERS.get(name)
        if kind is None and (name.endswith("-gpios") or name.endswith("-gpio")):
            kind = "#gpio-cells"
        if name in PHANDLE_LISTS or name.endswith("-supply") or (
                name.startswith("pinctrl-") and name[8:].isdigit()):
            return [ref(c) for c in cells]
        if name in FIXED:
            k, out = FIXED[name], []
            for i in range(0, len(cells), 1 + k):
                out.append(ref(cells[i]))
                out += [f"0x{c:x}" for c in cells[i + 1:i + 1 + k]]
            return out
        if kind:
            out, i = [], 0
            while i < len(cells):
                prov = phandles.get(cells[i])
                n = nodes.get(prov, {}).get(kind) if prov else None
                if n is None or len(n) != 4:
                    return [f"0x{c:x}" for c in cells]      # cannot parse: leave raw
                out.append(ref(cells[i]))
                k = struct.unpack(">I", n)[0]
                out += [f"0x{c:x}" for c in cells[i + 1:i + 1 + k]]
                i += 1 + k
            return out
        return [f"0x{c:x}" for c in cells]

    out = []
    for path in sorted(nodes):
        if path == "/__symbols__" or path.startswith("/__symbols__/"):
            continue
        out.append(f"{path} {{")
        for name in sorted(nodes[path]):
            if name in ("phandle", "linux,phandle"):
                continue
            v = nodes[path][name]
            if not v:
                text = ""
            elif is_strings(v):
                text = " = " + ", ".join('"%s"' % s.decode() for s in v[:-1].split(b"\0"))
            elif len(v) % 4 == 0:
                text = " = <" + " ".join(fmt(name, v)) + ">"
            else:
                text = " = [" + v.hex(" ") + "]"
            out.append(f"  {name}{text};")
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a, b = (render(parse(p)) for p in sys.argv[1:])
    diff = list(difflib.unified_diff(a, b, sys.argv[1], sys.argv[2], lineterm="", n=1))
    if not diff:
        print("IDENTICAL (content; phandle numbering and __symbols__ ignored)")
        return 0
    changed = sum(1 for l in diff if l[:1] in "+-" and l[:3] not in ("+++", "---"))
    print(f"DIFFERENT: {changed} changed lines")
    print("\n".join(diff))
    return 1


if __name__ == "__main__":
    sys.exit(main())
