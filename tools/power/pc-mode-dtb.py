# SPDX-License-Identifier: GPL-2.0-only
"""Turn a Book4 DTS into a PSCI platform-coordinated (PC) mode variant:
no PSCI power-domain hierarchy (so cpuidle-psci never calls SET_SUSPEND_MODE
to switch TrustZone to OS-initiated mode, as Hyper-V never does), flat CPU
idle states core C4 / cluster CL5 / system DRIPS carrying the composite
power_state, and the RSC flushing on the last CPU (cpu_pm) instead of on the
system power domain.
usage: python3 -I pc-mode-dtb.py IN.dts OUT.dts [pd]
  pd: set the PSCI StateType (power-down) bit 30 on the cluster/system states
"""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
pd = len(sys.argv) > 3 and sys.argv[3] == 'pd'
t = open(src).read()
ph = [int(x, 16) for x in re.findall(r'phandle = <0x([0-9a-f]+)>;', t)]
ph_cl, ph_sys = max(ph) + 1, max(ph) + 2
cl_param = 0x01000054 | (0x40000000 if pd else 0)
sys_param = 0x0200c354 | (0x40000000 if pd else 0)

# 1. CPUs: drop the "psci" power domain, keep "perf"; flat idle states
def fix_cpu(m):
    body = m.group(0)
    body = re.sub(r'power-domains = <0x[0-9a-f]+ (0x[0-9a-f]+ 0x[0-9a-f]+)>;',
                  r'power-domains = <\1>;', body)
    body = body.replace('power-domain-names = "psci", "perf";', 'power-domain-names = "perf";\n\t\t\tcpu-idle-states = <0x28 %#x %#x>;' % (ph_cl, ph_sys))
    return body
t, n = re.subn(r'cpu@[0-9a-f]+ \{.*?\n\t\t\};', fix_cpu, t, flags=re.S)
assert n == 12, n
assert t.count('cpu-idle-states') == 12

# 2. two more CPU idle states next to cpu-sleep-0
new_states = f'''
\t\t\tcluster-sleep-pc {{
\t\t\t\tcompatible = "arm,idle-state";
\t\t\t\tidle-state-name = "cl5";
\t\t\t\tarm,psci-suspend-param = <{cl_param:#x}>;
\t\t\t\tentry-latency-us = <0x898>;
\t\t\t\texit-latency-us = <0xfa0>;
\t\t\t\tmin-residency-us = <0x1b58>;
\t\t\t\tlocal-timer-stop;
\t\t\t\tphandle = <{ph_cl:#x}>;
\t\t\t}};

\t\t\tsystem-sleep-pc {{
\t\t\t\tcompatible = "arm,idle-state";
\t\t\t\tidle-state-name = "drips";
\t\t\t\tarm,psci-suspend-param = <{sys_param:#x}>;
\t\t\t\tentry-latency-us = <0x7d0>;
\t\t\t\texit-latency-us = <0xbb8>;
\t\t\t\tmin-residency-us = <0x2328>;
\t\t\t\tlocal-timer-stop;
\t\t\t\tphandle = <{ph_sys:#x}>;
\t\t\t}};
'''
t, n = re.subn(r'(cpu-sleep-0 \{.*?phandle = <0x28>;\n\t\t\t\};\n)', lambda m: m.group(1) + new_states, t, count=1, flags=re.S)
assert n == 1

# 3. psci: keep only compatible/method (no power-domain children)
t, n = re.subn(r'(\tpsci \{\n\t\tcompatible = "arm,psci-1.0";\n\t\tmethod = "smc";\n).*?(\n\t\};\n)',
               r'\1\2', t, count=1, flags=re.S)
assert n == 1

# 4. anything else attached to the system domain (the RSC): detach
t, n = re.subn(r'\n\t+power-domains = <0x2d>;', '', t)
print(f'cluster {cl_param:#x} system {sys_param:#x}; detached {n} node(s) from system_pd')
open(dst, 'w').write(t)
