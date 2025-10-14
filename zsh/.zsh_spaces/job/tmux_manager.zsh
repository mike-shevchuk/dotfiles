# 💡 TMUX Project Manager (Сесії та Демони) з детальним логуванням
ts() {
    echo "--- [DEBUG: ts() START] ---"

    # 1. Шляхи для сканування
    local project_dirs=(
        "$HOME/projects"
        "$HOME/dotfiles"
        "$HOME/work"
    )
    echo "DEBUG: Scanning directories: ${project_dirs[*]}"

    # 2. Інтерактивний вибір каталогу
    local project_list
    project_list=$(
        echo "."  # Дозволяє створити сесію у поточному каталозі
        for dir in "${project_dirs[@]}"; do
             if [ -d "$dir" ]; then
                 find "$dir" -mindepth 1 -maxdepth 1 -type d
             fi
        done
    )
    
    # ПЕРЕВІРКА: Чи fzf отримав список
    if [[ -z "$project_list" ]]; then
        echo "ERROR: Project list is empty. Check if directories exist or if fzf is working."
        return 1
    fi

    local target_dir
    target_dir=$(echo "$project_list" | fzf --prompt="Select project directory (ts): " --border --height=40%)

    if [[ -z "$target_dir" ]]; then
        echo "DEBUG: Selection cancelled by user."
        echo "--- [DEBUG: ts() END] ---"
        return 0
    fi
    
    # Обробка вибору поточної директорії
    if [[ "$target_dir" == "." ]]; then
        target_dir="$PWD"
    fi

    echo "DEBUG: Target directory selected: $target_dir"

    local session_name
    # Використовуємо ім'я каталогу як назву сесії
    session_name=$(basename "$target_dir" | tr . _)
    echo "DEBUG: Calculated session name: $session_name"

    # 3. Перевірка існування сесії
    if tmux has-session -t "$session_name" 2>/dev/null; then
        # СЕСІЯ ІСНУЄ
        echo "INFO: Session '$session_name' found. Attaching..."
        tmux switch-client -t "$session_name"
        echo "--- [DEBUG: ts() END] ---"
        return 0
    fi
    
    echo "INFO: Session '$session_name' does NOT exist."

    # 4. СЕСІЯ НЕ ІСНУЄ: Перевіряємо наявність скрипта налаштування
    local setup_script="$target_dir/.tmux_setup.sh"
    echo "DEBUG: Checking for setup script: $setup_script"

    if [ -f "$setup_script" ]; then
        # СЦЕНАРІЙ: Файл налаштування знайдено. Створюємо сесію та запускаємо скрипт.
        echo "INFO: Setup script found. Creating session and running setup."

        # 5a. Створення нової сесії
        tmux new-session -ds "$session_name" -c "$target_dir" -n 'Shell'
        echo "DEBUG: New detached session created: $session_name"

        # 5b. Запуск скрипта налаштування
        tmux send-keys -t "$session_name:0" "zsh $setup_script" C-m
        echo "DEBUG: Sent command 'zsh $setup_script' to window 0."
        
        # 5c. Приєднання
        tmux attach-session -t "$session_name"
        echo "INFO: Attached to session '$session_name'."
        echo "--- [DEBUG: ts() END] ---"
        return 0
    else
        # СЦЕНАРІЙ: Файл налаштування не знайдено. НЕ СТВОРЮЄМО сесію.
        echo "WARNING: No existing session and no .tmux_setup.sh found."
        echo "INFO: Aborting session creation."
        echo "--- [DEBUG: ts() END] ---"
        return 1
    fi
}



fjob() {
    local selected
    selected=$(jobs -l | fzf --prompt="Select Job: " --height=20% --layout=reverse --border --no-hscroll)
    if [[ -n "$selected" ]]; then
        local job_id=$(echo "$selected" | awk '{print $1}' | tr -d '[]%')
        fg %"$job_id"
    fi
}
alias jf='fjob'
