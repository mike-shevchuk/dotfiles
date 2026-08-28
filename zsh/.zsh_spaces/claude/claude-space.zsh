# Claude space — профілі Claude Code через CLAUDE_CONFIG_DIR.
# Активний профіль читається з ~/.claude-active (1 слово).
#   "default" (або файл відсутній) → живий ~/.claude, змінна не задається.
#   інша назва → CLAUDE_CONFIG_DIR=~/.claude-profiles/<name>.
# Керування профілями: just -g c-list | c-setup | c-save | c-switch | c-delete
# Перемикання діє з НАСТУПНОГО запуску `claude`, не всередині живої сесії.

claude() {
    local active_file="$HOME/.claude-active"
    local profiles_dir="$HOME/.claude-profiles"
    local p=default
    [[ -f "$active_file" ]] && p=$(<"$active_file")
    [[ -z "$p" ]] && p=default   # порожній/зіпсутий active-файл → default (не контейнер профілів)

    if [[ "$p" == default ]]; then
        command claude "$@"
    elif [[ -d "$profiles_dir/$p" ]]; then
        CLAUDE_CONFIG_DIR="$profiles_dir/$p" command claude "$@"
    else
        # активний профіль зник — не блокуємо запуск, падаємо на default
        echo "claude: профіль '$p' не знайдено у $profiles_dir — запускаю default" >&2
        command claude "$@"
    fi
}

# Показати активний профіль у промпті/при потребі: `claude-active`
claude-active() {
    local active_file="$HOME/.claude-active"
    [[ -f "$active_file" ]] && cat "$active_file" || echo default
}
