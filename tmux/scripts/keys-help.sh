#!/usr/bin/env bash
# keys-help.sh — grouped cheat-sheet of the custom tmux bindings defined in
# ~/.tmux.conf.local. Bound to: prefix ? (tmux display-popup -E).
# Scrollable via less; press q to close. Falls back to plain cat.
#
# This list is curated by hand (grouped for readability) — keep it in sync when
# you add/change a binding in ~/.tmux.conf.local. A drift is harmless and is
# caught the first time you try the stale key.
set -uo pipefail

C_TITLE='\033[1;35m'   # magenta bold
C_GROUP='\033[1;36m'   # cyan bold
C_KEY='\033[1;33m'     # yellow bold
C_DIM='\033[2m'
C_OFF='\033[0m'

row() { printf "  ${C_KEY}%-12s${C_OFF} %s\n" "$1" "$2"; }
grp() { printf "\n${C_GROUP}%s${C_OFF}\n" "$1"; }

render() {
    printf "${C_TITLE}tmux cheat-sheet${C_OFF}  ${C_DIM}(prefix = C-a · q to close)${C_OFF}\n"

    grp "Layouts"
    row "prefix C"   "Claude layout — nvim │ claude code │ shell"
    row "prefix D"   "DevOps layout — editor │ logs │ shell (3 panes)"
    row "prefix C-d" "Quad layout — 4 panes for log tailing"

    grp "Productivity popups"
    row "prefix A"   "Claude dashboard — all claude panes, jump to one"
    row "prefix j"   "Session switcher — fzf list + live preview"
    row "prefix W"   "Worktree → session — open a git worktree as a session"
    row "prefix R"   "Just menu — run a justfile recipe (global + project)"
    row "prefix T"   "Project switcher (ts) — create/attach from project dirs"
    row "prefix ?"   "This cheat-sheet (alias: prefix F1) — j/k scroll · /search · q quit"

    grp "Tools"
    row "prefix g"   "lazygit"
    row "prefix G"   "lazygit — Branches view"
    row "prefix o"   "yazi file manager (opens in a window)"
    row "prefix B"   "btop system monitor"
    row "prefix s"   "dotfiles stow status"
    row "prefix S"   "Mode-color theme picker (Style) — fzf presets or HTML custom"

    grp "Diff / compare (fzf branch picker, Enter = default branch)"
    row "prefix v"   "DiffView vs branch — Enter=base, Tab=pick head, C-t exact (2-dot), C-o uncommitted"
    row "prefix V"   "CodeDiff — VSCode-style two-tier diff: pick head + base branches (PR-style)"
    row "prefix C-v" "Diff MENU — pick platform (codediff/diffview/delta/difftastic/tig) + head + base"
    row "prefix M"   "delta side-by-side pager vs branch"
    row "prefix N"   "difftastic semantic diff vs branch"
    row "prefix O"   "pick branch → changed files → DiffView"
    printf "  ${C_DIM}in DiffView${C_OFF} C-j/C-k scroll · C-d/C-u half page · ]c/[c next/prev hunk · C-h/C-l panes\n"
    printf "  ${C_DIM}           ${C_OFF} from the file list C-j/C-k scroll the diff · zR all folds · zo expand one\n"

    grp "Scroll a pane (no prefix, no mouse)"
    row "S-PageUp"   "scroll one screen up — enters copy-mode automatically"
    row "S-PageDown" "scroll one screen down"
    row "S-Up/S-Down" "scroll 3 lines (Shift+arrows); exits at the bottom on its own"
    row "M-Up/M-Down" "same, Alt+arrows (only on terminals that send them)"
    printf "  ${C_DIM}in copy-mode${C_OFF} j/k · C-u/C-d · g/G · /search · q quit  (mouse wheel also works)\n"

    grp "Status bar"
    printf "  ${C_DIM}row 0${C_OFF} session · tabs · 🐍 python · 󰚩 claude · cpu · ram · clock\n"
    printf "  ${C_DIM}row 1${C_OFF} active pane: 🌿 branch · 🔀 PR#n · path · 🐍 python\n"
    printf "  ${C_DIM}border${C_OFF} per-pane claude state/uptime or command · path · git · python\n"

    printf "\n${C_DIM}Everything else: prefix : then 'list-keys', or prefix ? in base config.${C_OFF}\n"
}

if command -v less >/dev/null 2>&1; then
    render | less -R
else
    render
    printf '\npress any key…'
    read -rsn1 _ 2>/dev/null || true
fi
