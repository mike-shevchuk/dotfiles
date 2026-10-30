# --- LAN — who is on the home network, by MAC (macOS) ------------------------
#
# WHY — IPs float (DHCP, macOS private Wi-Fi MAC rotation), so anything that
# needs "the Pi" or "the projector" reads LAN_<LABEL>_IP from ~/dotfiles/.env,
# and this recipe keeps those lines true.
#
#   just -g lan        sweep, write, table → gum menu (no gum / no TTY: table only)
#   just -g lan scan   sweep, write, table
#   just -g lan name   sweep, then label the unknown devices
#   just -g mac-ip     same as `lan`
#
# ~/dotfiles/.lan-devices (untracked, repo is public): one `label MAC` per line.
# The Mac itself is always `mac`, by its IP — its MAC rotates, so it is not listed.
# Also writes MAC_IP to ~/dotfiles/.env and manjaro:~/.mac_ip.env.
# Off the home LAN only the Mac's IP is refreshed: a café's devices are not ours.

alias mac-ip := lan

# LAN devices by MAC: sweep → LAN_<LABEL>_IP in .env + MAC_IP (also on the Pi) → table → gum menu (scan · name)
[group('system')]
[no-cd]
lan action="":
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$PATH:/usr/sbin:/sbin" # route, arp, ping, ifconfig
    action="{{ action }}"
    devices=~/dotfiles/.lan-devices
    env_file=~/dotfiles/.env
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    rc=0

    case "$action" in
        ""|scan) ;;
        name) [ -t 0 ] && [ -t 2 ] && command -v gum >/dev/null || { echo "FAIL: lan name потребує TTY і gum" >&2; exit 2; } ;;
        *) echo "FAIL: невідома дія '$action' — є: scan | name" >&2; exit 2 ;;
    esac

    env_set() { # KEY VALUE — replace in place, never duplicate
        if grep -qx "$1=$2" "$env_file"; then
            return
        elif grep -q "^$1=" "$env_file"; then
            sed -i '' "s/^$1=.*/$1=$2/" "$env_file"; echo "  $1=$2 (замінено)" >&2
        else
            echo "$1=$2" >> "$env_file"; echo "  $1=$2 (додано)" >&2
        fi
    }

    scan() {
        echo "[1/4] IP мака (en1, fallback en0)..." >&2
        iface=en1; ip=$(ipconfig getifaddr en1 || true)
        [ -n "$ip" ] || { iface=en0; ip=$(ipconfig getifaddr en0 || true); }
        [ -n "$ip" ] || { echo "  FAIL — ні en1, ні en0 не мають IPv4" >&2; exit 1; }
        mac=$(ifconfig "$iface" | awk '/ether/{print $2}')
        gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
        echo "  OK ($ip · $iface · $mac · шлюз ${gw:-?})" >&2

        if [ "$gw" = 192.168.50.1 ]; then
            net=${gw%.*}
            echo "[2/4] sweep $net.1-254 (UDP 5353 + ping, паралельно)..." >&2
            # a sleeping iPhone ignores ping and ARP, but a UDP packet to its mDNS port wakes its Wi-Fi for a moment
            for i in $(seq 1 254); do (echo -n x > "/dev/udp/$net.$i/5353") >/dev/null 2>&1 & done
            wait
            for i in $(seq 1 254); do ping -c1 -t1 -q "$net.$i" >/dev/null 2>&1 & done
            wait
            arp -an -i "$iface" > "$tmp/arp"
            echo "  OK ($(grep -c ' at [0-9a-f]*:' "$tmp/arp") у ARP)" >&2
        else
            echo "[2/4] шлюз не 192.168.50.1 — не вдома, sweep пропущено" >&2
            : > "$tmp/arp"
        fi

        echo "[3/4] імена (DNS роутера, mDNS) і мітки..." >&2
        touch "$env_file" "$devices"
        python3 - "$tmp" "$ip" "$mac" "$devices" "$env_file" <<'PY'
    import re, subprocess, sys
    tmp, own_ip, own_mac, devices, env_file = sys.argv[1:]
    GW = "192.168.50.1"
    # DHCP name "espressif" catches most boards; a few common Espressif OUIs for the ones that hide it
    ESP_OUI = {"10:bd:a3", "24:0a:c4", "24:6f:28", "30:ae:a4", "34:85:18", "3c:71:bf", "40:4c:ca",
               "48:3f:da", "58:cf:79", "7c:df:a1", "84:f3:eb", "a4:cf:12", "dc:54:75", "ec:fa:bc", "f0:9e:9e"}
    PROJECTOR = re.compile(r"projector|проектор|epson|benq|optoma|viewsonic|xgimi|wemax|formovie", re.I)

    def key(label): return "LAN_" + label.upper().replace("-", "_") + "_IP"

    def dig(ip, *server):
        out = subprocess.run(["dig", "+short", "+time=1", "+tries=1", "-x", ip, *server],
                             capture_output=True, text=True).stdout.splitlines()
        return out[0].rstrip(".") if out and not out[0].startswith(";") else ""

    labels = {}  # mac → label
    for line in open(devices):
        p = line.split()
        if len(p) == 2 and not line.startswith("#"):
            labels[p[1].lower()] = p[0]
    prev = dict(l.strip().split("=", 1) for l in open(env_file) if re.match(r"LAN_\w+_IP=", l))

    seen = {}  # mac → (ip, name)
    for ip, raw in re.findall(r"\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-f:]+) on", open(f"{tmp}/arp").read()):
        m = ":".join(o.zfill(2) for o in raw.split(":"))  # arp drops leading zeros
        if not ip.startswith("192.168.50.") or ip in (GW, own_ip) or ip.endswith(".255") or len(raw.split(":")) != 6:
            continue
        seen[m] = (ip, dig(ip, f"@{GW}") or dig(ip, "@224.0.0.251", "-p", "5353"))

    for m, (ip, name) in seen.items():  # first sight of a recognisable device → it earns a label
        if m in labels:
            continue
        auto = None
        if "esp" in name.lower() or m[:8] in ESP_OUI:
            auto = "esp_" + m[-5:].replace(":", "")
        elif PROJECTOR.search(name) and "projector" not in labels.values():
            auto = "projector"
        if auto:
            labels[m] = auto
            open(devices, "a").write(f"{auto} {m}\n")
            print(f"  нова мітка: {auto} = {m} ({name or 'OUI Espressif'})", file=sys.stderr)

    rows, envs, unknown = [("mac", own_ip, own_mac, "mac", key("mac"))], [], []
    for m, label in labels.items():
        ip, name = seen.get(m, (None, ""))
        rows.append((label, ip, m, name, key(label)))
    table = [("LABEL", "IP", "MAC", "ІМʼЯ", "ЗМІНА")]
    for label, ip, m, name, k in rows:
        old = prev.get(k)
        if ip is None:
            table.append((label, old or "—", m, name, "offline"))
            continue
        envs.append(f"{k} {ip}")
        table.append((label, ip, m, name, "новий" if not old else "=" if old == ip else f"було {old}"))
    for m, (ip, name) in sorted(seen.items(), key=lambda s: int(s[1][0].rsplit(".", 1)[1])):
        if m not in labels:
            unknown.append(f"{ip} {m} {name or '?'}")
            table.append(("?", ip, m, name or "?", ""))

    open(f"{tmp}/env", "w").write("".join(e + "\n" for e in envs))
    open(f"{tmp}/unknown", "w").write("".join(u + "\n" for u in unknown))
    w = [max(len(r[i]) for r in table) for i in range(5)]
    for r in table:
        print("  ".join(c.ljust(n) for c, n in zip(r, w)).rstrip())
    PY
        [ $? -eq 0 ] || { echo "  FAIL — розбір скану" >&2; exit 1; }

        echo "[4/4] запис: $env_file + Pi ~/.mac_ip.env..." >&2
        env_set MAC_IP "$ip"
        while read -r k v; do env_set "$k" "$v"; done < "$tmp/env"
        cmd="printf 'MAC_IP=%s\n' $ip > ~/.mac_ip.env && cat ~/.mac_ip.env"
        echo "━━━ ssh ━━━  ssh -o BatchMode=yes -o ConnectTimeout=5 manjaro \"$cmd\"" >&2
        if out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 manjaro "$cmd"); then
            echo "  OK ($out)" >&2
        else
            echo "  FAIL — Pi недоступний; локальний .env оновлено" >&2; rc=1
        fi
    }

    name_device() {
        [ -s "$tmp/unknown" ] || { echo "  Невідомих немає" >&2; return; }
        pick=$(gum choose --header "Який пристрій назвати?" < "$tmp/unknown") || return
        read -r dev_ip dev_mac _ <<<"$pick"
        label=$(gum input --header "Мітка для $pick" --placeholder "projector") || return
        label=$(printf %s "$label" | tr '[:upper:]' '[:lower:]')
        if ! [[ $label =~ ^[a-z0-9][a-z0-9_-]*$ ]] || [ "$label" = mac ] || grep -q "^$label " "$devices"; then
            echo "  FAIL — мітка '$label' не підходить (a-z 0-9 _ -, не mac) або вже зайнята" >&2
            return
        fi
        echo "$label $dev_mac" >> "$devices"
        echo "  OK ($label = $dev_mac у $devices)" >&2
        env_set "LAN_$(printf %s "$label" | tr 'a-z-' 'A-Z_')_IP" "$dev_ip"
        grep -v " $dev_mac " "$tmp/unknown" > "$tmp/unknown.new"; mv "$tmp/unknown.new" "$tmp/unknown"
    }

    scan
    if [ "$action" = name ]; then
        name_device
    elif [ -z "$action" ] && [ -t 0 ] && [ -t 2 ] && command -v gum >/dev/null; then
        while :; do
            choice=$(gum choose --header "Що далі?" "назвати невідомий пристрій" "показати .env рядки" "вийти") || break
            case "$choice" in
                назвати*) name_device ;;
                показати*) grep -E '^(MAC_IP|LAN_[A-Z0-9_]+_IP)=' "$env_file" ;;
                *) break ;;
            esac
        done
    fi
    exit $rc
