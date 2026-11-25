# --- Hammerspoon: reload safely ------------------------------------------------
#
#   just -g hs            reload (refuses while a meeting records or is processed)
#   just -g hs reload force   reload anyway
#   just -g hs status     is Hammerspoon answering + what would block a reload
#
# WHY the guard: a reload once killed a live meeting (the Mac backup ffmpeg and meeting.py are hs.tasks).
# WHY a timer: `hs -c 'hs.reload()'` tears down the IPC port mid-call and has hung/crashed HS; scheduling the
# reload 1 s later lets the CLI return first. Never kill `hs` itself (CFMessagePort crash) — always `hs -q -t N`.

# reload Hammerspoon safely (guard: no live meeting) · status
[group('hs')]
[no-cd]
hs action="reload" force="":
    #!/usr/bin/env bash
    set -uo pipefail
    meet=~/.local/share/esp-deck/meetings
    blockers() {  # prints what a reload would kill, one per line
        pgrep -fl 'ffmpeg.*avfoundation' >/dev/null && echo "запис аудіо на Mac (ffmpeg) — іде мітинг"
        pgrep -fl 'helper/meeting.py' >/dev/null && echo "обробка мітингу (meeting.py) ще йде"
        find "$meet" -maxdepth 1 -name '*.mac.ulaw' -mmin -2 2>/dev/null | grep -q . && echo "плата пише мітинг (свіжий .mac.ulaw)"
        return 0
    }
    alive() { hs -q -t 5 -c 'return "ok"' 2>/dev/null | grep -q ok; }
    case "{{action}}" in
      status)
        echo "→ hs -q -t 5 -c 'return \"ok\"'" >&2
        alive && echo "  OK Hammerspoon відповідає" >&2 || echo "  FAIL Hammerspoon не відповідає" >&2
        b=$(blockers); [ -n "$b" ] && { echo "  reload зараз небезпечний:" >&2; echo "$b" | sed 's/^/    · /' >&2; } || echo "  reload безпечний" >&2 ;;
      reload|force)
        echo "[1/3] перевірка: чи не йде мітинг..." >&2
        b=$(blockers)
        if [ -n "$b" ] && [ "{{action}}{{force}}" != "reloadforce" ] && [ "{{action}}" != "force" ]; then
          echo "  FAIL reload зараз уб'є:" >&2; echo "$b" | sed 's/^/    · /' >&2
          echo "  дочекайся кінця або: just -g hs reload force" >&2; exit 1
        fi
        echo "  OK" >&2
        echo "[2/3] reload через 1 с (CLI повертається до reload)..." >&2
        echo "━━━ hs ━━━  hs -q -t 20 -c '_G.__reloadT = hs.timer.doAfter(1, hs.reload); return \"scheduled\"'" >&2
        hs -q -t 20 -c '_G.__reloadT = hs.timer.doAfter(1, hs.reload); return "scheduled"' >/dev/null 2>&1 || true
        echo "[3/3] чекаю, поки Hammerspoon підніметься..." >&2
        sleep 3
        for _ in $(seq 1 15); do alive && { echo "  OK Hammerspoon перезавантажено" >&2; exit 0; }; sleep 2; done
        echo "  FAIL Hammerspoon не відповідає 33 с — відкрий його вручну" >&2; exit 1 ;;
      *) echo "  FAIL невідома дія '{{action}}' — є: reload [force] | status" >&2; exit 2 ;;
    esac
