# TIL space — spaced repetition: показує один випадковий TIL
# у ПЕРШОМУ інтерактивному терміналі дня (guard-файл у /tmp).
# Вимкнути на сьогодні:  rm -f /tmp/til-shown-*  → покажеться знову;
#                        touch /tmp/til-shown-$(date +%F)  → сховати до завтра.
# Довідка: just -g til-help

_til_daily() {
    # тільки інтерактивний shell і тільки якщо є just + рецепт
    [[ -o interactive ]] || return 0
    command -v just >/dev/null 2>&1 || return 0

    local stamp="/tmp/til-shown-$(date +%F)"
    [[ -f "$stamp" ]] && return 0
    touch "$stamp"

    # тихий фейл — TIL-и опційні, термінал важливіший
    just -g til-random 2>/dev/null || true
}

_til_daily
