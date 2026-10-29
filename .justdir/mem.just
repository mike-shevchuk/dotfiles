# --- Memory (RAM/swap) — who eats it and what to do (macOS) -----------------
#
# WHY — 16 GB mac + ~30 Claude sessions: each session spawns its OWN copy of
# every MCP plugin (playwright = npm+node, aws-serverless = uv+python), so
# swap fills up and the machine hangs. These recipes show where the GB went
# and switch the heavy plugins off for NEW sessions (running ones keep theirs).
#
#   just -g mem                 overview: RAM, swap, pressure, groups, verdict
#   just -g mem-claude          every Claude session (tmux window) + its MCP kids, biggest first
#   just -g mcp-slim [plugins]  disable heavy MCP plugins globally (scope user)
#   just -g mcp-on plugin       enable a plugin only in the current dir (scope local, not committed)
#   just -g mcp-fat [plugins]   undo mcp-slim — enable globally again
#
# Memory = footprint (top MEM: counts compressed + swapped pages). Under heavy
# pressure `top` can fail ("sysmond service not found") → fallback to ps RSS,
# marked "(RSS, занижено)" because RSS misses compressed/swapped memory.

mem_plugins := "playwright@claude-plugins-official aws-serverless@claude-plugins-official"

# Overview: RAM, swap, memory pressure, compressor, groups (Claude/MCP/browsers/top-5) + verdict
[group('mem')]
mem: (_mem "all")

# Every Claude session (tmux session:window) = own memory + its MCP children, biggest first
[group('mem')]
mem-claude: (_mem "claude")

[private]
_mem view:
    #!/usr/bin/env python3
    import os, re, subprocess, sys
    from collections import defaultdict
    view = "{{view}}"
    sys.stdout.reconfigure(line_buffering=True)  # keep stdout/stderr in order
    err = lambda s: print(s, file=sys.stderr)
    sh = lambda *a: subprocess.run(a, capture_output=True, text=True).stdout

    # ── memory per pid: footprint from top, ps RSS as fallback ──
    err("→ top -l 1 -stats pid,mem   (footprint per process)")
    try:
        r = subprocess.run(["top", "-l", "1", "-stats", "pid,mem"], capture_output=True, text=True, timeout=30)
        top_out = r.stdout if r.returncode == 0 else ""
    except Exception:
        top_out = ""
    unit = {"B": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30}
    mem = {}
    for line in top_out.splitlines():
        m = re.match(r"\s*(\d+)\s+([\d.]+)([BKMG])", line)
        if m:
            mem[int(m[1])] = float(m[2]) * unit[m[3]]
    procs = {}  # pid -> (ppid, rss_bytes, cmd)
    for line in sh("ps", "-axo", "pid=,ppid=,rss=,command=").splitlines():
        p = line.split(None, 3)
        if len(p) == 4:
            procs[int(p[0])] = (int(p[1]), int(p[2]) * 1024, p[3])
    how = "footprint"
    if len(mem) < len(procs) // 2:
        err("  top failed under pressure → fallback: ps RSS")
        how = "RSS, занижено"
        mem = {pid: v[1] for pid, v in procs.items()}
    gb = lambda b: f"{b / (1 << 30):5.2f} GB"
    kids = defaultdict(list)
    for pid, (ppid, _, _) in procs.items():
        kids[ppid].append(pid)
    def tree(pid):
        out = [pid]
        for k in kids[pid]:
            out += tree(k)
        return out

    # ── classify ──
    def is_session(cmd):
        a = cmd.split()
        return os.path.basename(a[0]) == "claude" and (len(a) == 1 or not a[1].startswith("bg-"))
    def mcp_name(cmd):
        for pat, name in (("@playwright/mcp", "playwright"), ("aws-serverless-mcp", "aws-serverless"),
                          ("pyright", "pyright (LSP)")):
            if pat in cmd:
                return name
        return os.path.basename(cmd.split()[0])
    sessions = [pid for pid, v in procs.items() if is_session(v[2]) and not is_session(procs.get(v[0], (0, 0, ""))[2])]
    panes = {}
    for line in sh("tmux", "list-panes", "-a", "-F", "#{pane_pid}\t#{session_name}:#{window_index} #{window_name}").splitlines():
        pp, _, label = line.partition("\t")
        panes[int(pp)] = label
    def pane_of(pid):
        while pid > 1:
            if pid in panes:
                return panes[pid]
            pid = procs.get(pid, (1,))[0]
        return "(не в tmux)"
    claimed = set()
    rows, mcp = [], defaultdict(lambda: [0, 0.0])
    for s in sessions:
        own, kid_mem = mem.get(s, 0), 0.0
        claimed.add(s)
        for k in kids[s]:
            if "shell-snapshots" in procs[k][2]:
                continue  # Bash-tool shell, not an MCP server
            t = tree(k)
            claimed.update(t)
            m = sum(mem.get(x, 0) for x in t)
            kid_mem += m
            name = mcp_name(procs[k][2])
            mcp[name][0] += 1
            mcp[name][1] += m
        rows.append((own + kid_mem, own, kid_mem, s, pane_of(s)))
    rows.sort(reverse=True)

    if view == "claude":
        print(f"── Claude sessions: {len(rows)}  ({how}) ──")
        print(f"  {'TOTAL':>8}  {'own':>8}  {'MCP':>8}  {'pid':>6}  tmux")
        for tot, own, km, pid, label in rows:
            print(f"  {gb(tot)}  {gb(own)}  {gb(km)}  {pid:>6}  {label}")
        print(f"  {gb(sum(r[0] for r in rows))}  разом")
        err("")
        err("Що далі: перезапусти найважчу сесію (/exit → claude --continue) — MCP-копії звільняться;")
        err("         нові сесії без важких MCP: just -g mcp-slim")
        sys.exit(0)

    # ── system numbers ──
    total = int(sh("sysctl", "-n", "hw.memsize"))
    sw = dict(re.findall(r"(\w+) = ([\d.]+)M", sh("sysctl", "-n", "vm.swapusage")))
    sw_used, sw_tot = float(sw.get("used", 0)) / 1024, float(sw.get("total", 0)) / 1024
    level = sh("sysctl", "-n", "kern.memorystatus_vm_pressure_level").strip()
    level_txt = {"1": "normal", "2": "WARN", "4": "CRITICAL"}.get(level, level or "?")
    free_pct = re.search(r"free percentage: (\d+)%", sh("memory_pressure", "-Q"))
    vm = sh("vm_stat")
    page = int(re.search(r"page size of (\d+)", vm)[1])
    vmv = lambda k: int(re.search(rf"{k}:\s+(\d+)", vm)[1]) * page
    print(f"── RAM {total / (1 << 30):.0f} GB · swap {sw_used:.1f}/{sw_tot:.1f} GB · pressure {level_txt}"
          f" (вільно {free_pct[1] if free_pct else '?'}%) ──")
    print(f"  compressor: {gb(vmv('Pages stored in compressor'))} стиснуто → займає {gb(vmv('Pages occupied by compressor'))} RAM"
          f" · wired {gb(vmv('Pages wired down'))}")

    # ── groups ──
    print(f"\n── хто їсть памʼять ({how}) ──")
    print(f"  {gb(sum(r[1] for r in rows))}  Claude сесії ×{len(rows)} (без MCP)   → just -g mem-claude")
    for name, (n, m) in sorted(mcp.items(), key=lambda x: -x[1][1]):
        if m >= 50 << 20:
            print(f"  {gb(m)}  MCP {name} ×{n}")
    def app(cmd):
        m = re.search(r"/([^/]+)\.app/", cmd)
        b = os.path.basename(cmd.split()[0])
        return m[1] if m else ("claude bg-* (фонові)" if b == "claude" else b)
    other = defaultdict(lambda: [0, 0.0])
    for pid, (_, _, cmd) in procs.items():
        if pid not in claimed:
            a = app(cmd)
            other[a][0] += 1
            other[a][1] += mem.get(pid, 0)
    browsers = ("Thorium Browser", "Google Chrome", "Safari", "Firefox", "Arc", "Brave Browser", "Microsoft Edge")
    for a in browsers:
        n, m = other.pop(a, (0, 0))
        if m >= 50 << 20:
            print(f"  {gb(m)}  браузер {a} ×{n}")
    for a, (n, m) in sorted(other.items(), key=lambda x: -x[1][1])[:5]:
        print(f"  {gb(m)}  {a} ×{n}")

    # ── verdict ──
    print()
    tight = level in ("2", "4") or (sw_tot and sw_used / sw_tot > 0.8)
    if tight:
        print("Вердикт: памʼяті НЕ вистачає — мак лізе в swap і буде підвисати.")
        dup = sum(m for n, m in mcp.values() if n > 1)
        if dup:
            print(f"  MCP-копії по сесіях тримають ~{dup / (1 << 30):.1f} GB — найлегша економія.")
    else:
        print("Вердикт: памʼяті вистачає.")
    err("")
    err("Що далі:")
    err("  just -g mem-claude     яку сесію перезапустити (найважчі зверху)")
    err("  just -g mcp-slim       нові сесії без playwright/aws-serverless (запущені — до рестарту)")
    err("  just -g mcp-on <p>     увімкнути плагін лише в цьому проєкті")

# Disable heavy MCP plugins globally (scope user) — NEW sessions start without them
[group('mem')]
mcp-slim plugins=mem_plugins:
    #!/usr/bin/env bash
    set -uo pipefail
    set -- {{plugins}}; i=0; fail=0
    for p in "$@"; do
        i=$((i+1))
        echo "→ [$i/$#] claude plugin disable $p --scope user" >&2
        claude plugin disable "$p" --scope user && echo "  OK" >&2 || { echo "  FAIL" >&2; fail=1; }
    done
    echo "" >&2
    echo "Нові сесії стартують без них; уже запущені тримають копії до рестарту." >&2
    echo "Потрібен у проєкті:  cd <проєкт> && just -g mcp-on <plugin>   (scope local, не комітиться)" >&2
    echo "Повернути все:       just -g mcp-fat" >&2
    exit $fail

# Enable one plugin only in the current directory (scope local — not committed)
[group('mem')]
[no-cd]
mcp-on plugin:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "→ claude plugin enable {{plugin}} --scope local   (in $PWD)" >&2
    claude plugin enable "{{plugin}}" --scope local && echo "  OK — діє для нових сесій у $PWD" >&2 || { echo "  FAIL" >&2; exit 1; }

# Undo mcp-slim — enable the plugins globally again (scope user)
[group('mem')]
mcp-fat plugins=mem_plugins:
    #!/usr/bin/env bash
    set -uo pipefail
    set -- {{plugins}}; i=0; fail=0
    for p in "$@"; do
        i=$((i+1))
        echo "→ [$i/$#] claude plugin enable $p --scope user" >&2
        claude plugin enable "$p" --scope user && echo "  OK" >&2 || { echo "  FAIL" >&2; fail=1; }
    done
    exit $fail
