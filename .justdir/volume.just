# Гучність macOS
#
#   jg vol            — меню (gum)
#   jg vol 40         — встановити 40%
#   jg vol up | down  — ±10%   (jg vol down 5 — свій крок)
#   jg vol mute | unmute | toggle | status

# Гучність: число/up/down [крок]/mute/unmute/toggle/status, без аргументу — меню
[group('system')]
vol action="" step="10":
    #!/usr/bin/env bash
    set -uo pipefail
    # each osascript call costs ~2-4s, so read once and write+read once
    read_state() { osascript -e 'set s to get volume settings' -e 'return ((output volume of s) as text) & " " & ((output muted of s) as text)'; }
    show() { set -- $1; echo "  гучність: $1%$( [ "$2" = true ] && echo ' · mute')" >&2; }
    apply() {
        echo "━━━ osascript ━━━  osascript -e '$1'" >&2
        osascript -e "$1" -e 'set s to get volume settings' -e 'return ((output volume of s) as text) & " " & ((output muted of s) as text)'
    }
    clamp() { local v=$1; (( v < 0 )) && v=0; (( v > 100 )) && v=100; echo $v; }

    act="{{action}}"
    [[ "{{step}}" =~ ^[0-9]+$ ]] || { echo "FAIL — крок має бути числом: '{{step}}'" >&2; exit 1; }
    state=$(read_state); cur=${state%% *}; mut=${state##* }
    if [ -z "$act" ]; then
        act=$(gum choose --header "Гучність ❯ зараз $cur%$( [ "$mut" = true ] && echo ' (mute)')" \
            "up" "down" "0" "25" "50" "75" "100" "mute" "unmute" "status" </dev/tty) || exit 0
    fi

    case "$act" in
      up)               state=$(apply "set volume output volume $(clamp $(( cur + {{step}} )))") ;;
      down)             state=$(apply "set volume output volume $(clamp $(( cur - {{step}} )))") ;;
      mute)             state=$(apply "set volume output muted true") ;;
      unmute)           state=$(apply "set volume output muted false") ;;
      toggle)           [ "$mut" = true ] && n=false || n=true; state=$(apply "set volume output muted $n") ;;
      status)           ;;
      *[!0-9]*|'')      echo "FAIL — невідомо '$act'. Приклади: jg vol 40 · up · down 5 · mute · toggle · status" >&2; exit 1 ;;
      *)                state=$(apply "set volume output volume $(clamp "$act")") ;;
    esac
    show "$state"
