# --- Screen mirroring (iPad / Sidecar) --------------------------------------
#
# Drives Control Center → Screen Mirroring through Hammerspoon's accessibility
# API (hammerspoon/.hammerspoon/modules/mirror.lua). Sidecar is wireless, so the
# iPad can sit in the next room — nothing is plugged in and the iPad is never
# touched. It does need to be awake, on the same Wi-Fi and the same Apple
# Account, and Hammerspoon needs Accessibility permission.
#
#   just -g mirror          # duplicate this Mac's screen onto the iPad
#   just -g mirror-extend   # use the iPad as an extra display instead
#   just -g mirror-off      # disconnect
#   just -g mirror-toggle   # connect ⇄ disconnect
#   just -g mirror-status   # what is attached right now
#   just -g mirror-list     # devices Screen Mirroring is offering
#   just -g mirror-pick     # fzf over those devices
#
# Every recipe takes the device name as its argument; it defaults to "iPad".

# The resolution step is not optional decoration: left alone, macOS mirrors at
# 1180x820 and a tiling WM fits about three columns in it. `res` takes a mode,
# `max` (the default), or `keep` to leave whatever macOS chose.

# Duplicate this Mac's screen onto the iPad (wireless Sidecar)
[group('mirror')]
mirror device="iPad" res="max":
    #!/usr/bin/env bash
    set -uo pipefail
    front=$(just -f "{{justfile()}}" _mirror-front)
    just -f "{{justfile()}}" _mirror connect "{{device}}" mirror || exit 1
    [ "{{res}}" = "keep" ] || just -f "{{justfile()}}" mirror-res "{{res}}"
    just -f "{{justfile()}}" _mirror-refocus "$front"

# The gentlest of the three: this monitor keeps its own resolution, so a tiling
# WM has no reason to re-lay the row and nothing gets pushed past the edge. The
# focus is still restored afterwards, because attaching any display re-tiles.

# Use the iPad as an extra display rather than a duplicate — nothing here moves
[group('mirror')]
mirror-extend device="iPad":
    #!/usr/bin/env bash
    set -uo pipefail
    front=$(just -f "{{justfile()}}" _mirror-front)
    just -f "{{justfile()}}" _mirror connect "{{device}}" extend || exit 1
    just -f "{{justfile()}}" _mirror-refocus "$front"

# Disconnect the iPad (and bring the monitor backlight back if mirror-solo dimmed it)
[group('mirror')]
mirror-off device="iPad":
    #!/usr/bin/env bash
    set -uo pipefail
    just -f "{{justfile()}}" _mirror disconnect "{{device}}"
    # DDC only reaches the monitor once the mirrored set is gone.
    if [ -f "$HOME/.cache/hs/monitor-luminance" ]; then
        sleep 2
        just -f "{{justfile()}}" _mirror-restore-brightness
    fi

# Connect if disconnected, disconnect if connected
[group('mirror')]
mirror-toggle device="iPad" mode="mirror":
    @just -f "{{justfile()}}" _mirror toggle "{{device}}" "{{mode}}"

# Whether the device is attached, and which displays macOS currently has
[group('mirror')]
mirror-status device="iPad":
    @just -f "{{justfile()}}" _mirror status "{{device}}"

# Devices Screen Mirroring is offering right now — name / kind / on|off
[group('mirror')]
mirror-list:
    @just -f "{{justfile()}}" _mirror list

# fzf over the offered devices, then connect the chosen one
[group('mirror')]
mirror-pick mode="mirror":
    #!/usr/bin/env bash
    set -uo pipefail
    devs=$(just -f "{{justfile()}}" _mirror list) || exit 1
    [ -n "$devs" ] || { echo "  FAIL — no devices offered" >&2; exit 1; }
    dev=$(printf '%s\n' "$devs" \
        | fzf --delimiter='\t' --with-nth=1,2,3 --prompt='mirror to > ' --height=40% --reverse \
        | cut -f1)
    [ -n "$dev" ] || { echo "  cancelled" >&2; exit 0; }
    just -f "{{justfile()}}" _mirror connect "$dev" "{{mode}}"

# Resolution of the mirrored set — no argument lists what the iPad offers
[group('mirror')]
mirror-res res="":
    #!/usr/bin/env bash
    set -uo pipefail
    dp=/opt/homebrew/bin/displayplacer
    [ -x "$dp" ] || { echo "  FAIL — displayplacer not installed (brew install displayplacer)" >&2; exit 1; }

    # A mirrored pair is one "id:<a>+<b>" group in displayplacer's own output;
    # <a> is the Sidecar display, and its mode list is what limits the pair.
    group=$("$dp" list | tail -1 | grep -oE 'id:[0-9A-Fa-f-]+\+[0-9A-Fa-f-]+' | head -1)
    [ -n "$group" ] || { echo "  FAIL — nothing is mirrored right now (run: just -g mirror)" >&2; exit 1; }
    sidecar=${group#id:}; sidecar=${sidecar%%+*}

    if [ -z "{{res}}" ]; then
        echo "→ resolutions the mirrored display can take:" >&2
        "$dp" list | awk -v id="$sidecar" '
            $0 ~ "^Persistent screen id: " id {f=1; next}
            /^Persistent screen id:/ {f=0}
            f && /^  mode .*hz:60/ {
                match($0, /res:[0-9]+x[0-9]+/); r=substr($0, RSTART+4, RLENGTH-4)
                if (!(r in seen)) { seen[r]=1
                                    printf "  %s%s\n", r, ($0 ~ /current mode/) ? "   <- current" : "" }
            }' | sort -t x -k1,1n -k2,2n
        echo "  set one with:  just -g mirror-res 1600x1112" >&2
        exit 0
    fi

    want="{{res}}"
    if [ "$want" = "max" ]; then
        # Widest mode wins: PaperWM fits one more column per ~600px of width.
        want=$("$dp" list | awk -v id="$sidecar" '
            $0 ~ "^Persistent screen id: " id {f=1; next}
            /^Persistent screen id:/ {f=0}
            f && /^  mode .*hz:60/ { match($0, /res:[0-9]+x[0-9]+/); print substr($0, RSTART+4, RLENGTH-4) }
        ' | sort -t x -k1,1n -k2,2n | tail -1)
        [ -n "$want" ] || { echo "  FAIL — could not read the mode list" >&2; exit 1; }
        echo "→ largest mode offered: $want" >&2
    fi

    echo "→ setting mirrored resolution to $want ..." >&2
    if "$dp" "$group res:$want hz:60 color_depth:4 enabled:true origin:(0,0) degree:0" >/dev/null 2>&1; then
        echo "  OK — $want" >&2
    else
        echo "  FAIL — $want is not one of the offered modes (see: just -g mirror-res)" >&2
        exit 1
    fi

# ORDER MATTERS. While a mirrored set is up, macOS exposes only the Sidecar
# display and the physical monitor is unreachable over DDC (m1ddc lists nothing
# and returns a negative error code). So the backlight has to be dimmed BEFORE
# Sidecar attaches, and can only be restored AFTER it detaches.

# Everything on the iPad, this monitor dark — backlight to 0, then mirror
[group('mirror')]
mirror-solo device="iPad" res="max":
    #!/usr/bin/env bash
    set -uo pipefail
    m1ddc=$(command -v m1ddc || echo /opt/homebrew/bin/m1ddc)
    [ -x "$m1ddc" ] || { echo "  FAIL — m1ddc not installed (brew install m1ddc)" >&2; exit 1; }

    front=$(just -f "{{justfile()}}" _mirror-front)
    read_luminance() { "$m1ddc" get luminance 2>/dev/null | tr -dc '0-9-'; }

    cur=$(read_luminance)
    case "$cur" in
        ''|-*)  # a mirror is already hiding the monitor — drop it so DDC answers
            echo "→ monitor is behind an active mirror set; dropping Sidecar first ..." >&2
            just -f "{{justfile()}}" _mirror disconnect "{{device}}" >/dev/null || true
            sleep 2
            cur=$(read_luminance)
            ;;
    esac
    case "$cur" in
        ''|-*) echo "  FAIL — the monitor does not answer over DDC" >&2; exit 1 ;;
    esac

    save="$HOME/.cache/hs/monitor-luminance"
    mkdir -p "$(dirname "$save")"
    printf '%s\n' "$cur" > "$save"
    echo "→ monitor backlight $cur → 0 (saved)" >&2
    "$m1ddc" set luminance 0 >/dev/null 2>&1

    if ! just -f "{{justfile()}}" _mirror connect "{{device}}" mirror; then
        # Never leave the user staring at a dark monitor with no iPad.
        "$m1ddc" set luminance "$cur" >/dev/null 2>&1
        rm -f "$save"
        echo "  FAIL — could not attach {{device}}; monitor backlight restored to $cur" >&2
        exit 1
    fi
    [ "{{res}}" = "keep" ] || just -f "{{justfile()}}" mirror-res "{{res}}"
    just -f "{{justfile()}}" _mirror-refocus "$front"
    echo "  OK — the picture lives on the iPad now; bring the monitor back with: just -g mirror-wake" >&2

# Leave solo mode: drop Sidecar, then bring the monitor backlight back
[group('mirror')]
mirror-wake device="iPad":
    @just -f "{{justfile()}}" mirror-off "{{device}}"

# Put the saved backlight back — only meaningful once Sidecar is already down
[group('mirror')]
[private]
_mirror-restore-brightness:
    #!/usr/bin/env bash
    set -uo pipefail
    save="$HOME/.cache/hs/monitor-luminance"
    [ -f "$save" ] || exit 0
    m1ddc=$(command -v m1ddc || echo /opt/homebrew/bin/m1ddc)
    prev=$(tr -dc '0-9' < "$save")
    [ -n "$prev" ] || prev=100
    echo "→ monitor backlight → $prev ..." >&2
    "$m1ddc" set luminance "$prev" >/dev/null 2>&1
    rm -f "$save"
    echo "  OK — $prev" >&2

# Screen mirroring cheatsheet
[group('mirror')]
mirror-help:
    #!/usr/bin/env bash
    cat >&2 <<'EOF'
    mirror-*  —  кинути екран на iPad (Sidecar, бездротово)

    iPad може лежати в сусідній кімнаті: нічого не втикаємо, iPad не чіпаємо.
    Треба щоб він не спав, був у тій же Wi-Fi і тому ж Apple Account.

    ЩОДЕННЕ
      mirror              дублювати цей екран на iPad (одразу максимальна
                          роздільність; `mirror iPad keep` — не чіпати)
      mirror-extend       iPad як ДОДАТКОВИЙ екран (для роботи зручніше)
      mirror-off          від'єднати
      mirror-toggle       туди-сюди
      mirror-status       підключено? які дисплеї зараз
      mirror-list         що взагалі пропонує macOS
      mirror-pick         fzf по пристроях

    ЩОБ ВСЕ ПОМІЩАЛОСЬ
      mirror-res          показати доступні роздільності дзеркала
      mirror-res 1600x1112   поставити конкретну
      mirror-res max      одразу найбільшу, яку вміє iPad

      У дзеркалі macOS тисне обидва екрани до спільної роздільності —
      за замовчуванням 1180x820, тому "нічого не влазить". Піднімаєш — влазить.

      Заміряно на PaperWM (23 вікна): 1180x820 -> видно 3 колонки,
      2360x1640 -> видно 5. Решта вікон не зникає, PaperWM паркує їх
      за краєм смужкою в 1px — прокрути, і вони повернуться.

    ТІЛЬКИ НА iPad, МОНІТОР ГАСНЕ
      mirror-solo             погасити монітор (DDC) + дзеркало на iPad
      mirror-solo iPad 1600x1112   те саме + одразу роздільність
      mirror-wake             повернути монітор (від'єднує Sidecar)

      Поки дзеркало активне, фізичний монітор через DDC недоступний —
      macOS показує лише дзеркальний набір. Тому гасимо ДО підключення,
      а вмикаємо ПІСЛЯ від'єднання. Якщо iPad не підключився — яскравість
      повертається сама, у темряві не залишишся.

    ВВІД З БОКУ iPad
      Sidecar прокидає на Mac лише апаратну клавіатуру та Apple Pencil.
      Трекпад/миша, підключені до iPad, НЕ працюють — це обмеження Sidecar.
      Рішення: підключи клавіатуру з тачпадом до Mac, а не до iPad.

      Ім'я пристрою — перший аргумент, дефолт "iPad":
        just -g mirror "iPad Мішка"

    БЕЗ ТЕРМІНАЛУ
      Менюбар:  📱 не підключено · 🪞 підключено · ⏳ підключається
                клік → mirror / extend / disconnect / вибір пристрою
      Хоткеї:   ctrl+alt+shift+M — тогл
                ctrl+alt+shift+P — вибір пристрою

    MIRROR ЧИ EXTEND
      mirror  дублює екран — і роздільність падає до iPad (~1180x795).
              Так працює Sidecar, це не баг. Показати щось комусь — ок.
      extend  лишає монітор як є, додає iPad збоку. Для роботи — це.
      Режим міняється на льоту, від'єднуватись не треба.

    ЩО ПОБАЧИШ ПІД ЧАС РОБОТИ (це механіка, не збої)
      • на секунду відкриється й закриється панель Control Center
      • смикнеться курсор і повернеться на місце
      • підключення триває 5-15 с

    КОЛИ НЕ ПРАЦЮЄ
      "is not offered ... (available: none)"   iPad спить / далеко / інший Apple Account
      "did not come up in 25s"                 те саме — розбуди iPad і повтори
      "Hammerspoon is not running"             запусти Hammerspoon
      "no 'hs' CLI"                            у консолі Hammerspoon: hs.ipc.cliInstall()

      Діагностика завжди починається з `mirror-list`: якщо iPad там не видно —
      проблема не в скрипті, а в тому, що macOS його не бачить.
      Зависнути мовчки не може: у модулі є watchdog, відповідь прийде завжди.

    ЯК ЦЕ ВЛАШТОВАНО
      У macOS немає API "підключи цей iPad". Тому модуль
      hammerspoon/.hammerspoon/modules/mirror.lua керує справжньою панеллю
      Control Center → Screen Mirroring через accessibility API і звідти ж
      читає стан. Рецепти лише просять Hammerspoon це виконати й чекають
      на відповідь у ~/.cache/hs/mirror.txt

    НАЛАШТУВАННЯ — блок M.config у mirror.lua
      device / mode / connect_timeout / notify
    EOF

# id of the window that is focused right now (empty if none) — printed on stdout
[group('mirror')]
[private]
_mirror-front:
    #!/usr/bin/env bash
    set -uo pipefail
    command -v hs >/dev/null 2>&1 || exit 0
    timeout 8 hs -c 'local w = hs.window.frontmostWindow(); return w and tostring(w:id()) or ""' 2>/dev/null \
        | tr -dc '0-9' || true

# Put the focus back where it was, so a tiling WM scrolls that window into view
#
# Attaching a display re-tiles everything. Under PaperWM the row is longer than
# the screen and the overflow is parked past the edge, so the window you were
# typing in — the terminal you drove this from — can end up off-screen with no
# way to reach it from the iPad. Re-focusing it makes PaperWM scroll it back.
[group('mirror')]
[private]
_mirror-refocus id="":
    #!/usr/bin/env bash
    set -uo pipefail
    [ -n "{{id}}" ] || exit 0
    command -v hs >/dev/null 2>&1 || exit 0
    sleep 1   # let the WM finish re-tiling for the new screen first
    echo "→ bringing the window you were using back into view ..." >&2
    timeout 8 hs -c 'local w = hs.window.get({{id}}); if w then w:focus() end; return "ok"' >/dev/null 2>&1 || true

# Ask Hammerspoon to drive the Screen Mirroring pane, then wait for its answer
[group('mirror')]
[private]
_mirror cmd device="iPad" mode="":
    #!/usr/bin/env bash
    set -uo pipefail

    lua="${MIRROR_LUA:-}"
    if [ -z "$lua" ]; then
        for candidate in "$HOME/.hammerspoon/modules/mirror.lua" \
                         "$HOME/dotfiles/hammerspoon/.hammerspoon/modules/mirror.lua"; do
            [ -f "$candidate" ] && { lua="$candidate"; break; }
        done
    fi
    [ -n "$lua" ] || { echo "  FAIL — mirror.lua not found in ~/.hammerspoon/modules or ~/dotfiles (set MIRROR_LUA to override)" >&2; exit 1; }
    command -v hs >/dev/null 2>&1 || { echo "  FAIL — no 'hs' CLI; run hs.ipc.cliInstall() inside Hammerspoon" >&2; exit 1; }
    pgrep -x Hammerspoon >/dev/null 2>&1 || { echo "  FAIL — Hammerspoon is not running" >&2; exit 1; }

    res="$HOME/.cache/hs/mirror.txt"
    mkdir -p "$(dirname "$res")"
    rm -f "$res"
    echo "→ screen mirroring: {{cmd}} {{device}} {{mode}} ..." >&2

    # `hs -c` keeps streaming the Hammerspoon console back over its socket, so a
    # slow call would hang here on unrelated log chatter. Fire it and forget it:
    # mirror.lua answers into $res, and its watchdog guarantees an answer lands.
    timeout 5 hs -c "dofile([[$lua]]).cli([[{{cmd}}]],[[{{device}}]],[[{{mode}}]])" >/dev/null 2>&1 || true

    for _ in $(seq 1 90); do
        [ -f "$res" ] && break
        sleep 1
    done
    [ -f "$res" ] || { echo "  FAIL — Hammerspoon gave no answer in 90s" >&2; exit 1; }

    verdict=$(head -1 "$res")
    case "$verdict" in
        OK*) echo "  OK ${verdict#OK }" >&2 ;;
        *)   echo "  FAIL ${verdict#FAIL }" >&2 ;;
    esac
    tail -n +2 "$res"
    [ "${verdict%% *}" = "OK" ]
