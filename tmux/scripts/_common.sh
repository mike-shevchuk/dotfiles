#!/usr/bin/env bash
# _common.sh — shared helpers for the tmux popup scripts (session-switch,
# claude-dashboard, just-menu, worktree-session). Sourced, not executed.
#
# Popups run via `display-popup -E`; on a fatal error we print the reason and
# wait for a keypress so the popup doesn't flash shut before it can be read.
# Portable to bash 3.2 (macOS).

# die <message> — report and abort, holding the popup open until a keypress.
die() {
    printf '%s\n' "$*" >&2
    printf 'press any key…' >&2
    read -rsn1 _ 2>/dev/null || true
    exit 1
}

# need <command> [install-hint] — require a command, else die with a hint.
need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not installed${2:+ — $2}"
}
