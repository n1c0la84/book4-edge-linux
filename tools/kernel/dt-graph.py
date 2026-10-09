#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""How the hardware is connected, from the live device tree.

Reads the tree the kernel booted with (/sys/firmware/devicetree/base, no root
needed) and the driver each node bound to (of_node links under /sys/devices),
and turns every cross-reference into an edge:

  graph      OF graph data paths (remote-endpoint), folded to the devices
  supply     *-supply regulators
  gpio       *-gpios / *-gpio (with pin numbers)
  irq        interrupts / interrupts-extended (with the line)
  clock, phy, reset, power, interconnect, iommu, dma, mbox, dai, ...
  bus        children of I2C / SPI / SPMI / SoundWire / USB controllers

  dt-graph.py json > dt.json                    # everything
  dt-graph.py dot --focus LABEL[,LABEL] [--depth N] [--kinds graph,phy,...]
              [--disabled] > view.dot            # a focused view for Graphviz
"""
import argparse, json, os, struct, sys

BASE = '/sys/firmware/devicetree/base'

# property -> (kind, #cells property of the provider)
SPEC = {
    'clocks': ('clock', '#clock-cells'), 'phys': ('phy', '#phy-cells'),
    'resets': ('reset', '#reset-cells'), 'power-domains': ('power', '#power-domain-cells'),
    'interconnects': ('interconnect', '#interconnect-cells'),
    'iommus': ('iommu', '#iommu-cells'), 'dmas': ('dma', '#dma-cells'),
    'mboxes': ('mbox', '#mbox-cells'), 'sound-dai': ('dai', '#sound-dai-cells'),
    'pwms': ('pwm', '#pwm-cells'), 'io-channels': ('adc', '#io-channel-cells'),
    'thermal-sensors': ('thermal', '#thermal-sensor-cells'),
    'nvmem-cells': ('nvmem', None), 'interrupts-extended': ('irq', '#interrupt-cells'),
    'qcom,smem-states': ('smem', '#qcom,smem-state-cells'),
}
# single-phandle properties worth drawing
SINGLE = {'remote-endpoint': 'graph', 'memory-region': 'memory', 'qcom,ipc': 'ipc',
          'usb-role-switch': 'usb', 'phy-handle': 'phy', 'ddc-i2c-bus': 'i2c',
          'cooling-device': 'cooling', 'mode-switch': None, 'orientation-switch': None}
BUS_COMPAT = ('i2c', 'spi', 'spmi', 'soundwire', 'swr', 'usb', 'qup', 'geni', 'pcie')
SKIP_TOP = ('__symbols__', '__fixups__', '__local_fixups__', 'aliases', 'chosen')


def read_tree(base):
    nodes = {}
    for root, dirs, files in os.walk(base):
        rel = '/' + os.path.relpath(root, base).replace('\\', '/')
        rel = '/' if rel == '/.' else rel
        if rel.split('/')[1:2] and rel.split('/')[1] in SKIP_TOP:
            dirs[:] = []
            continue
        props = {}
        for f in files:
            try:
                props[f] = open(os.path.join(root, f), 'rb').read()
            except OSError:
                pass
        nodes[rel] = props
    return nodes


def u32s(b):
    return list(struct.unpack('>%dI' % (len(b) // 4), b[:len(b) // 4 * 4]))


def text(b):
    return b.rstrip(b'\0').replace(b'\0', b', ').decode(errors='replace') if b else ''


def labels(base):
    sym = os.path.join(base, '__symbols__')
    out = {}
    if os.path.isdir(sym):
        for l in sorted(os.listdir(sym)):
            p = text(open(os.path.join(sym, l), 'rb').read())
            out.setdefault(p, []).append(l)
    return out


def drivers():
    out = {}
    for root, dirs, files in os.walk('/sys/devices'):
        if 'of_node' in os.listdir(root) if os.path.isdir(root) else False:
            try:
                p = os.path.realpath(os.path.join(root, 'of_node'))
                d = os.path.realpath(os.path.join(root, 'driver'))
            except OSError:
                continue
            if '/devicetree/base' in p and os.path.exists(os.path.join(root, 'driver')):
                out.setdefault(p.split('/devicetree/base', 1)[1] or '/', set()).add(os.path.basename(d))
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
    return out


def build(base=BASE):
    raw = read_tree(base)
    lab = labels(base)
    drv = drivers()
    ph = {}
    for p, props in raw.items():
        if 'phandle' in props:
            ph[u32s(props['phandle'])[0]] = p

    def cells(p, name, default=0):
        b = raw.get(p, {}).get(name)
        return u32s(b)[0] if b else default

    def anonymous(p):
        # graph plumbing, or a sub-node with neither compatible nor label
        # (e.g. /sound/wsa-dai-link/cpu): folded into its parent device
        name = p.rsplit('/', 1)[-1]
        if name.split('@')[0] in ('port', 'ports', 'endpoint', 'in-ports', 'out-ports'):
            return True
        return (p.count('/') > 1 and 'compatible' not in raw.get(p, {})
                and not lab.get(p) and p.split('/')[1] not in ('thermal-zones', 'reserved-memory'))

    def owner(p):
        parts = p.split('/')
        while len(parts) > 2 and anonymous('/'.join(parts)):
            parts.pop()
        return '/'.join(parts) or '/'

    def port_of(p):
        for part in reversed(p.split('/')):
            if part.startswith('port'):
                return part
        return ''

    nodes, edges = {}, []
    for p, props in raw.items():
        name = p.rsplit('/', 1)[-1] or '/'
        if p != '/' and anonymous(p):
            continue
        status = text(props.get('status', b'okay')) or 'okay'
        nodes[p] = {
            'path': p, 'name': name, 'labels': lab.get(p, []),
            'compatible': text(props.get('compatible', b'')),
            'status': 'okay' if status in ('okay', 'ok') else status,
            'driver': sorted(drv.get(p, [])),
        }

    def add(src, dst, kind, prop, info=''):
        s, d = owner(src), owner(dst)
        if s != d:
            edges.append({'from': s, 'to': d, 'kind': kind, 'prop': prop, 'info': info})

    def irq_parent(p):
        q = p
        while q:
            b = raw.get(q, {}).get('interrupt-parent')
            if b:
                return ph.get(u32s(b)[0])
            q = q.rsplit('/', 1)[0] if q != '/' else ''
        return None

    for p, props in raw.items():
        for k, v in props.items():
            if k in SINGLE and len(v) == 4:
                t = ph.get(u32s(v)[0])
                if t and SINGLE[k]:
                    info = (port_of(p) + ' -> ' + port_of(t)) if k == 'remote-endpoint' else ''
                    add(p, t, SINGLE[k], k, info)
            elif k.endswith('-supply') and len(v) == 4:
                t = ph.get(u32s(v)[0])
                if t:
                    add(p, t, 'supply', k)
            elif (k.endswith('-gpios') or k.endswith('-gpio') or k == 'gpios') and len(v) >= 4:
                c = u32s(v)
                i = 0
                while i < len(c):
                    t = ph.get(c[i])
                    if not t:
                        break
                    n = cells(t, '#gpio-cells', 2)
                    add(p, t, 'gpio', k, 'pin %d' % c[i + 1] if n else '')
                    i += 1 + n
            elif k in SPEC:
                kind, cname = SPEC[k]
                c = u32s(v)
                i = 0
                while i < len(c):
                    t = ph.get(c[i])
                    if not t:
                        break
                    n = cells(t, cname, 0) if cname else 0
                    args = c[i + 1:i + 1 + n]
                    info = ''
                    if kind == 'irq' and args:
                        info = 'line %d' % args[1] if len(args) > 2 else 'line %d' % args[0]
                    add(p, t, kind, k, info)
                    i += 1 + n
        if 'interrupts' in props:
            t = irq_parent(p)
            if t:
                c = u32s(props['interrupts'])
                n = cells(t, '#interrupt-cells', 1) or 1
                for j in range(0, len(c), n):
                    a = c[j:j + n]
                    info = 'line %d' % (a[1] if len(a) > 2 else a[0])
                    add(p, t, 'irq', 'interrupts', info)

    # bus children (devices addressed on a controller's bus)
    for p in nodes:
        parent = p.rsplit('/', 1)[0] or '/'
        if parent in nodes and parent != '/' and '@' in p.rsplit('/', 1)[-1]:
            pc = nodes[parent]['compatible'].lower() + ' ' + nodes[parent]['name']
            if any(b in pc for b in BUS_COMPAT) and not parent.endswith('/soc@0'):
                edges.append({'from': parent, 'to': p, 'kind': 'bus', 'prop': '', 'info': ''})
    for p, n in nodes.items():
        parent = p.rsplit('/', 1)[0] or '/'
        if (parent in nodes and parent != '/' and '@' not in n['name'] and n['compatible']
                and nodes[parent]['compatible'] and 'operating-points' not in n['compatible']):
            edges.append({'from': p, 'to': parent, 'kind': 'part', 'prop': '', 'info': 'part of'})

    # remote-endpoint is stated at both ends: keep one edge per pair
    seen, uniq = set(), []
    for e in edges:
        if e['kind'] == 'graph':
            a, b = e['info'].split(' -> ') if ' -> ' in e['info'] else ('', '')
            key = tuple(sorted([(e['from'], a), (e['to'], b)]))
            if key in seen:
                continue
            seen.add(key)
        uniq.append(e)
    return {'nodes': list(nodes.values()), 'edges': uniq}


def short(n):
    if n['labels']:
        return n['labels'][0]
    parts = n['path'].split('/')
    # unlabelled children (e.g. a connector) are named with parent and bus
    if len(parts) > 3 and '@' not in parts[-1]:
        return ' / '.join(parts[-3:])
    return n['name']


def dot(g, focus, depth, kinds, disabled):
    by = {n['path']: n for n in g['nodes']}
    lab = {l: n['path'] for n in g['nodes'] for l in n['labels']}
    start = set()
    for f in focus:
        p = lab.get(f) or (f if f in by else None)
        if not p:
            sys.exit('unknown node or label: %s' % f)
        start.add(p)
    E = [e for e in g['edges'] if (not kinds or e['kind'] in kinds) and e['from'] in by and e['to'] in by]
    keep, frontier = set(start), set(start)
    for _ in range(depth):
        nxt = set()
        for e in E:
            if e['from'] in frontier and e['to'] not in keep:
                nxt.add(e['to'])
            if e['to'] in frontier and e['from'] not in keep:
                nxt.add(e['from'])
        if not disabled:
            nxt = {p for p in nxt if by[p]['status'] == 'okay'}
        keep |= nxt
        frontier = nxt
    color = {'part': '#111827', 'graph': '#2563eb', 'phy': '#7c3aed', 'gpio': '#d97706', 'irq': '#dc2626',
             'supply': '#16a34a', 'bus': '#6b7280', 'usb': '#0891b2', 'clock': '#9ca3af'}
    out = ['digraph dt {', '  rankdir=LR; node [shape=box, style="rounded,filled", fontname="sans", fontsize=10];',
           '  edge [fontname="sans", fontsize=8];']
    names = {}
    for p in keep:
        names.setdefault(short(by[p]), []).append(p)

    def title(p):
        t = short(by[p])
        if len(names[t]) > 1:       # same name twice: add the bus it sits on
            t = p.rsplit('/', 2)[-2] + ' / ' + t
        return t

    for p in sorted(keep):
        n = by[p]
        fill = '#dcfce7' if n['driver'] else ('#fef9c3' if n['status'] == 'okay' else '#f3f4f6')
        lines = [title(p)]
        if n['compatible']:
            lines.append(n['compatible'].split(', ')[0])
        lines.append(', '.join(n['driver']) if n['driver'] else ('no driver' if n['status'] == 'okay' else n['status']))
        border = ', penwidth=2' if p in start else ''
        out.append('  "%s" [label="%s", fillcolor="%s"%s];' % (p, '\\n'.join(lines), fill, border))
    seen = set()
    for e in E:
        if e['from'] in keep and e['to'] in keep:
            key = (e['from'], e['to'], e['kind'], e['info'])
            if key in seen:
                continue
            seen.add(key)
            lbl = e['prop'] if e['kind'] != 'graph' else e['info']
            if e['info'] and e['kind'] != 'graph':
                lbl += ' ' + e['info']
            out.append('  "%s" -> "%s" [label="%s", color="%s"];' % (
                e['from'], e['to'], lbl, color.get(e['kind'], '#9ca3af')))
    out.append('}')
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('mode', choices=('json', 'dot'))
    ap.add_argument('--base', default=BASE)
    ap.add_argument('--focus', default='')
    ap.add_argument('--depth', type=int, default=2)
    ap.add_argument('--kinds', default='')
    ap.add_argument('--disabled', action='store_true', help='also follow disabled nodes')
    a = ap.parse_args()
    g = build(a.base)
    if a.mode == 'json':
        json.dump(g, sys.stdout, indent=1)
    else:
        print(dot(g, [f for f in a.focus.split(',') if f], a.depth,
                  set(k for k in a.kinds.split(',') if k), a.disabled))


if __name__ == '__main__':
    main()
