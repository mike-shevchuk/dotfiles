# mise — менеджер версій інструментів (https://mise.jdx.dev)
#
# Що вміє mise:
#   mise install neovim@0.12.0   — встановити конкретну версію
#   mise use neovim@0.12.0       — встановити + зафіксувати в .mise.toml
#   mise ls                      — показати всі встановлені інструменти
#   mise ls-remote neovim        — показати всі доступні версії neovim
#   mise current                 — показати активні версії
#   mise up                      — оновити всі інструменти до останніх
#   mise prune                   — видалити невикористовувані версії
#   mise rm neovim               — видалити інструмент повністю
#
# mise автоматично перемикає версії по директоріях через .mise.toml
# Наприклад, можна мати node 20 в одному проекті і node 22 в іншому

# Встановити mise (менеджер версій інструментів)
mise-install:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v mise >/dev/null 2>&1; then
        echo "mise вже встановлено: $(mise --version)"
        exit 0
    fi
    echo "Встановлюю mise..."
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm mise
    elif command -v brew >/dev/null 2>&1; then
        brew install mise
    else
        curl https://mise.run | sh
    fi
    echo "mise встановлено: $(mise --version)"
    echo ""
    echo "Додай в .zshrc (якщо ще не додано):"
    echo '  eval "$(mise activate zsh)"'

# Встановити Neovim 0.12 через mise (замінює системний nvim)
nvim-install version="0.12.0":
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v mise >/dev/null 2>&1; then
        echo "mise не знайдено. Спочатку: just mise-install"
        exit 1
    fi
    echo "Встановлюю neovim v{{version}} через mise..."
    mise install neovim@{{version}}
    mise use -g neovim@{{version}}
    echo ""
    echo "Готово! Перевір:"
    nvim --version | head -1

# Показати всі інструменти встановлені через mise
mise-ls:
    @mise ls

# Показати доступні версії neovim
nvim-versions:
    @mise ls-remote neovim | tail -20
