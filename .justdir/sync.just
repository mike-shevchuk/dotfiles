# =============================================================================
# sync.just — multi-machine sync for dotfiles + zettelkasten,
#             plus shared CLAUDE.md storage and an fzf-powered help launcher.
# =============================================================================
#
# WHY THIS EXISTS
# ═══════════════
# Two machines (Mac + Linux) share:
#   • ~/dotfiles      — public git repo (configs, hooks, statusline)
#   • ~/zettelkasten  — private git repo (notes, project context, CLAUDE.md
#                        source-of-truth files under claude_code/claudes/)
#
# Without discipline, each machine diverges silently:
#   machine A edits CLAUDE.md → push
#   machine B edits CLAUDE.md → push fails (non-fast-forward) or, worse,
#                                user force-pushes and overwrites A's work.
#
# Sync is `git pull --rebase --autostash` + `git push` for BOTH repos.
# Run it on demand (`just sync`) or in the background on shell startup
# (see README → "Auto-pull on shell startup").
#
# CLAUDE.md STORAGE MODEL
# ═══════════════════════
# Source of truth lives in ~/zettelkasten/claude_code/claudes/{repo}/CLAUDE.md.
# Each repo (or "global") gets its own subdir. Optional .target file inside
# stores the canonical symlink target, so `just claudes-link` is idempotent
# and reproduces the layout on a fresh machine.
#
#   ~/zettelkasten/claude_code/claudes/
#     global/
#       CLAUDE.md       ← content (single source of truth)
#       .target         ← "~/CLAUDE.md"   (where the symlink should live)
#     rescue-serverless/
#       CLAUDE.md
#       .target         ← "~/code/rescue-serverless/CLAUDE.md"
#
# On every machine, `just claudes-link` creates / refreshes the symlinks
# so opening any of those repos in Claude Code reads the synced file.
#
# WHY NOT JUST KEEP CLAUDE.md IN dotfiles?
# ─────────────────────────────────────────
# 1. dotfiles is public; CLAUDE.md often holds personal/project context.
# 2. zettelkasten already syncs notes — collocating .md files is natural.
# 3. Per-repo CLAUDE.md doesn't belong in the dotfiles tree at all.
#
# FULL SCENARIO — DAY IN THE LIFE
# ═══════════════════════════════
# First-time setup on a NEW machine:
#   1. clone:  git clone git@github.com:mike-shevchuk/dotfiles.git ~/dotfiles
#              git clone git@github.com:mike-shevchuk/zettelekasten.git ~/zettelkasten
#   2. setup:  cd ~/dotfiles && just setup        # stows everything
#   3. links:  just claudes-link                  # builds CLAUDE.md symlinks
#   4. verify: just claudes-status                # green = symlinks resolve
#
# Every workday:
#   morning →  just sync                          # pull both repos
#   work    →  edit, commit normally
#   evening →  just sync                          # push both repos
#
# Adding a NEW repo whose CLAUDE.md should be synced:
#   cd ~/code/some-repo
#   just -f ~/dotfiles/justfile claudes-add some-repo "$(pwd)/CLAUDE.md"
#   # → moves CLAUDE.md into zettelkasten, leaves a symlink, commits zk
#
# Editing CLAUDE.md from EITHER machine:
#   just sync          (pull)
#   $EDITOR ~/CLAUDE.md   # writes through the symlink to zettelkasten
#   just sync          (push)
#
# CONFLICT HANDLING
# ═════════════════
# `git pull --rebase --autostash` is the safest pull:
#   • --rebase keeps history linear (no surprise merge commits)
#   • --autostash hides any in-flight WIP during the rebase, then restores it
# If a real conflict shows up, sync stops with the rebase paused; resolve
# manually (`git rebase --continue` / `git rebase --abort`).
#
# DAEMON MODE
# ═══════════
# For paranoid background sync, see ~/dotfiles/zsh/.zsh_spaces/sync/auto_pull.zsh
# (sourced from .zshrc when enabled). It runs `git pull --rebase --autostash`
# in the background on every new shell — pulls only, never pushes, so it's
# safe to run constantly.
# =============================================================================

# Pull + push both ~/dotfiles and ~/zettelkasten — daily-driver sync command
sync:
    #!/usr/bin/env bash
    # Visibility (per CLAUDE.md "Justfile recipes — visibility" rules):
    #   • announce each step to stderr
    #   • show resolved git command before running it
    #   • indent git output so the structure is scannable
    set -e
    repos=("$HOME/dotfiles" "$HOME/zettelkasten")
    total=${#repos[@]}
    i=0
    for repo in "${repos[@]}"; do
        i=$((i+1))
        echo "" >&2
        echo "[$i/$total] $repo" >&2
        if [ ! -d "$repo/.git" ]; then
            echo "  SKIP — not a git repo" >&2
            continue
        fi
        cd "$repo"
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")
        echo "  branch: $branch" >&2
        echo "  ━━━ git -C $repo pull --rebase --autostash ━━━" >&2
        if ! git pull --rebase --autostash 2>&1 | sed 's/^/    /' >&2; then
            echo "  FAIL — pull conflict, resolve manually then re-run sync" >&2
            exit 1
        fi
        if git rev-parse '@{u}' >/dev/null 2>&1; then
            ahead=$(git rev-list '@{u}..HEAD' --count)
            if [ "$ahead" -gt 0 ]; then
                echo "  ━━━ git -C $repo push  ($ahead commits ahead) ━━━" >&2
                git push 2>&1 | sed 's/^/    /' >&2
                echo "  OK (pushed)" >&2
            else
                echo "  OK (nothing to push)" >&2
            fi
        else
            echo "  no upstream for '$branch' — skipping push" >&2
        fi
    done
    echo "" >&2

# Wire ~/dotfiles git hooks to .githooks/ (pre-push warns about unpushed zettelkasten)
hooks-install:
    #!/usr/bin/env bash
    # Sets core.hooksPath so version-controlled hooks under ~/dotfiles/.githooks/
    # are used instead of the default per-clone .git/hooks/. Idempotent — safe
    # to re-run from `just setup`.
    set -e
    repo="$HOME/dotfiles"
    hooks_dir="$repo/.githooks"
    if [ ! -d "$hooks_dir" ]; then
        echo "FAIL — $hooks_dir does not exist" >&2
        exit 1
    fi
    current=$(git -C "$repo" config --get core.hooksPath 2>/dev/null || echo "")
    if [ "$current" = "$hooks_dir" ]; then
        echo "  OK — core.hooksPath already set to $hooks_dir" >&2
    else
        echo "→ git -C $repo config core.hooksPath $hooks_dir" >&2
        git -C "$repo" config core.hooksPath "$hooks_dir"
        echo "  installed" >&2
    fi
    # Ensure scripts are executable (some filesystems / clones lose +x)
    for f in "$hooks_dir"/*; do
        [ -f "$f" ] || continue
        if [ ! -x "$f" ]; then
            chmod +x "$f"
            echo "  chmod +x $(basename "$f")" >&2
        fi
    done

# Pull-only variant — use when you don't want to push (e.g. on shell startup)
sync-pull:
    #!/usr/bin/env bash
    for repo in "$HOME/dotfiles" "$HOME/zettelkasten"; do
        [ -d "$repo/.git" ] || continue
        cd "$repo"
        if ! git rev-parse '@{u}' >/dev/null 2>&1; then
            echo "→ $repo: no upstream for $(git symbolic-ref --short HEAD), skipping" >&2
            continue
        fi
        echo "→ pulling $repo..." >&2
        git pull --rebase --autostash 2>&1 | sed 's/^/    /' >&2 || true
    done

# fzf-powered recipe picker — shows recipe + comment, previews body, runs on Enter
help:
    #!/usr/bin/env bash
    # `just --list` formats lines as "  <name>   # <comment>", which fzf
    # filters fuzzily. Preview window calls `just --show <name>` to render
    # the recipe body so you can see exactly what it will run.
    if ! command -v fzf >/dev/null 2>&1; then
        echo "fzf not installed — falling back to plain list" >&2
        echo "install: brew install fzf  /  apt install fzf" >&2
        exec just --list --unsorted
    fi
    chosen=$(just --list --unsorted --color=always 2>/dev/null \
        | tail -n +2 \
        | fzf --ansi \
              --header='Select a recipe (Enter = run, Esc = quit, Ctrl-Y = copy)' \
              --preview='just --show {1} 2>/dev/null' \
              --preview-window=right:65%:wrap \
              --bind='ctrl-y:execute-silent(echo {1} | pbcopy 2>/dev/null || echo {1} | xclip -sel clip 2>/dev/null)+abort' \
              --height=80% \
              --layout=reverse)
    name=$(echo "$chosen" | awk '{print $1}')
    [ -z "$name" ] && exit 0
    echo "→ running: just $name" >&2
    just "$name"

# Re-create symlinks for every claudes/{repo}/ that has a .target file
claudes-link:
    #!/usr/bin/env bash
    # Reads ~/zettelkasten/claude_code/claudes/*/.target and ensures each
    # listed path is a symlink to the corresponding CLAUDE.md.
    # Idempotent — safe to run repeatedly. Prints what it did.
    set -e
    base="$HOME/zettelkasten/claude_code/claudes"
    if [ ! -d "$base" ]; then
        echo "FAIL — $base does not exist (clone zettelkasten first)" >&2
        exit 1
    fi
    found=0
    for dir in "$base"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        src="${dir}CLAUDE.md"
        target_file="${dir}.target"
        if [ ! -f "$src" ]; then
            echo "  SKIP $name — no CLAUDE.md inside $dir" >&2
            continue
        fi
        if [ ! -f "$target_file" ]; then
            echo "  SKIP $name — no .target file (set with: just claudes-add)" >&2
            continue
        fi
        target=$(eval echo "$(cat "$target_file" | tr -d '[:space:]')")
        found=$((found+1))
        if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
            echo "  OK   $name → $target (already linked)" >&2
            continue
        fi
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            backup="${target}.bak.$(date +%s)"
            echo "  WARN $name — $target exists as a regular file" >&2
            echo "       backing up to $backup before replacing" >&2
            mv "$target" "$backup"
        fi
        mkdir -p "$(dirname "$target")"
        ln -sfn "$src" "$target"
        echo "  LINK $name → $target" >&2
    done
    if [ "$found" -eq 0 ]; then
        echo "  no .target files found — claudes/ has no registered repos yet" >&2
        echo "  register one with: just claudes-add <name> <path/to/CLAUDE.md>" >&2
    fi

# Show health of every CLAUDE.md symlink registered under claudes/
claudes-status:
    #!/usr/bin/env bash
    base="$HOME/zettelkasten/claude_code/claudes"
    if [ ! -d "$base" ]; then
        echo "no $base" >&2; exit 1
    fi
    green='\033[32m'; red='\033[31m'; yellow='\033[33m'; dim='\033[2m'; reset='\033[0m'
    printf "\n  %-22s  %-7s  %s\n" "REPO" "STATUS" "TARGET"
    printf "  %-22s  %-7s  %s\n" "----" "------" "------"
    for dir in "$base"/*/; do
        name=$(basename "$dir")
        src="${dir}CLAUDE.md"
        target_file="${dir}.target"
        if [ ! -f "$target_file" ]; then
            printf "  %-22s  ${dim}%-7s  no .target file${reset}\n" "$name" "n/a"
            continue
        fi
        target=$(eval echo "$(cat "$target_file" | tr -d '[:space:]')")
        if [ ! -e "$target" ]; then
            printf "  %-22s  ${red}%-7s${reset}  %s ${dim}(missing)${reset}\n" "$name" "BROKEN" "$target"
        elif [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
            printf "  %-22s  ${green}%-7s${reset}  %s\n" "$name" "OK" "$target"
        elif [ -L "$target" ]; then
            printf "  %-22s  ${yellow}%-7s${reset}  %s ${dim}→ $(readlink "$target")${reset}\n" "$name" "DRIFT" "$target"
        else
            printf "  %-22s  ${yellow}%-7s${reset}  %s ${dim}(regular file, not a symlink)${reset}\n" "$name" "DRIFT" "$target"
        fi
    done
    printf "\n"

# Usage:    just claudes-add <repo-name> <path/to/existing/CLAUDE.md>
# Example:  just claudes-add rescue-serverless ~/code/rescue-serverless/CLAUDE.md
# Register a new CLAUDE.md under claudes/: move into zettelkasten, symlink back, commit + push
claudes-add name path:
    #!/usr/bin/env bash
    set -e
    name="{{name}}"
    path=$(eval echo "{{path}}")
    base="$HOME/zettelkasten/claude_code/claudes"
    dest_dir="$base/$name"
    dest_file="$dest_dir/CLAUDE.md"
    if [ ! -f "$path" ] && [ ! -L "$path" ]; then
        echo "FAIL — '$path' not found" >&2
        exit 1
    fi
    if [ -L "$path" ]; then
        echo "FAIL — '$path' is already a symlink ($(readlink "$path"))" >&2
        echo "       did you already register this repo? Check 'just claudes-status'" >&2
        exit 1
    fi
    if [ -e "$dest_file" ]; then
        echo "FAIL — $dest_file already exists; refusing to overwrite" >&2
        echo "       remove it manually if you really want to re-register" >&2
        exit 1
    fi
    mkdir -p "$dest_dir"
    echo "→ moving $path → $dest_file" >&2
    mv "$path" "$dest_file"
    echo "→ writing .target ($path)" >&2
    # Store the path with $HOME expanded back to ~ so it's portable across machines
    printf "%s\n" "${path/#$HOME/\~}" > "$dest_dir/.target"
    echo "→ creating symlink $path → $dest_file" >&2
    ln -sfn "$dest_file" "$path"
    echo "" >&2
    echo "  ━━━ git -C ~/zettelkasten add + commit + push ━━━" >&2
    cd "$HOME/zettelkasten"
    git add "claude_code/claudes/$name/"
    git commit -m "Register $name CLAUDE.md under claudes/" 2>&1 | sed 's/^/    /' >&2
    git push 2>&1 | sed 's/^/    /' >&2
    echo "" >&2
    echo "  OK — $name registered. Run 'just claudes-status' to verify." >&2
