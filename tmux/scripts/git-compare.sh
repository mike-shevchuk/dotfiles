#!/usr/bin/env bash
# git-compare.sh — open a diff between current branch and a target branch.
# Used by tmux popup bindings (prefix V/M/N/O).
#
# EVERY mode prompts for the target branch via fzf. Default branch is pre-selected
# (cursor on first line) so you can just hit Enter for the common case.
#
# Tools (1st arg):
#   review       — GitHub-PR-style unified diff via delta; pick HEAD (default current)
#                  + BASE (default origin's main/master) branches, diff BASE→HEAD
#   codediff     — VSCode-style two-tier diff (line + char), C-powered, moved-code detection
#   diffview     — DiffView in lz (LazyVIM nvim) — side-by-side
#   delta        — delta side-by-side pager (falls back to git diff if delta missing)
#   difftastic   — difftastic semantic diff (falls back to git diff if difft missing)
#   files        — fzf list of changed files vs target; opens picked file in DiffView
#
# Default branch detection: origin/HEAD → origin/main → origin/master → origin/develop.

set -uo pipefail

TOOL="${1:-diffview}"

# ─── Detect default branch (used as pre-selection in fzf) ──────────────────
detect_default_branch() {
    local symref
    symref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
    if [[ -n "$symref" ]]; then
        echo "$symref"
        return 0
    fi
    for candidate in origin/main origin/master origin/develop; do
        if git rev-parse --verify --quiet "$candidate" >/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# ─── fzf branch picker (default branch first → cursor lands on it) ─────────
pick_branch() {
    local current default
    current=$(git branch --show-current 2>/dev/null)
    default=$(detect_default_branch || true)

    {
        # Default branch first — cursor lands on line 1, just hit Enter for common case
        [[ -n "$default" ]] && echo "$default"
        # Then everything else (sorted, dedupe, exclude current branch + default)
        git branch -a --format='%(refname:short)' \
            | grep -v '^HEAD' \
            | grep -v "^${current}$" \
            | grep -v "^${default}$" \
            | sort -u
    } | fzf \
        --prompt='compare against (Enter=default): ' \
        --height 60% \
        --border \
        --preview 'git log --oneline -10 {}' \
        --preview-window 'right:50%'
}

# ─── fzf picker with a caller-chosen default on line 1 ─────────────────────
# Lists all local + remote branches; $1 is pre-selected first (Enter picks it).
pick_branch_default() {
    local def="$1" prompt="$2"
    {
        [[ -n "$def" ]] && echo "$def"
        git branch -a --format='%(refname:short)' \
            | grep -v '^HEAD' \
            | grep -v "^${def}$" \
            | sort -u
    } | fzf --prompt="$prompt" --height 60% --border \
            --preview 'git log --oneline -10 {}' --preview-window 'right:50%'
}

# ─── Pick target branch ────────────────────────────────────────────────────
# review picks its OWN head + base branches inside the case below; the other
# modes compare the working tree against a single picked branch.
if [[ "$TOOL" != "review" ]]; then
    TARGET=$(pick_branch)
    if [[ -z "$TARGET" ]]; then
        echo "no branch picked — aborted" >&2
        exit 0
    fi
fi

# ─── Tool dispatch ──────────────────────────────────────────────────────────
case "$TOOL" in
    review)
        # GitHub-PR-style review of any two refs. Two fzf pickers:
        #   1) HEAD — the branch to review   (default: current branch)
        #   2) BASE — the branch to compare against (default: origin's default,
        #             e.g. origin/main or origin/master)
        # Then a unified delta diff in the PR direction (BASE → HEAD).
        #
        # If HEAD is your CURRENT branch, the diff runs to the WORKING TREE from
        # the merge-base with BASE, so uncommitted edits are included (preview
        # your in-progress PR). For any other HEAD it's the committed three-dot
        # BASE...HEAD — exactly GitHub's "Files changed" for that PR.
        cur=$(git branch --show-current 2>/dev/null)
        base_def=$(detect_default_branch || echo "origin/master")
        HEAD_REF=$(pick_branch_default "$cur" "PR head — review THIS branch (Enter=current): ")
        [[ -z "$HEAD_REF" ]] && { echo "no head branch picked — aborted" >&2; exit 0; }
        BASE_REF=$(pick_branch_default "$base_def" "PR base — compare against (Enter=$base_def): ")
        [[ -z "$BASE_REF" ]] && { echo "no base branch picked — aborted" >&2; exit 0; }

        if [[ "$HEAD_REF" == "$cur" ]]; then
            spec=$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo "$BASE_REF")
        else
            spec="$BASE_REF...$HEAD_REF"
        fi

        # Empty diff → clear message instead of a blank pager (looks broken).
        if git diff --quiet "$spec" 2>/dev/null; then
            printf '\033[1;33m✓ Nothing to review.\033[0m\n\n' >&2
            printf '  \033[1m%s\033[0m has no changes beyond \033[1m%s\033[0m.\n\n' "$HEAD_REF" "$BASE_REF" >&2
            printf '  Pick a feature branch as head, or a different base.\n\n' >&2
            printf '  press any key…' >&2
            read -n1 -rs _ 2>/dev/null || true
            exit 0
        fi
        echo "→ PR diff: $BASE_REF → $HEAD_REF" >&2
        if command -v delta >/dev/null 2>&1; then
            git diff "$spec" \
                | delta --line-numbers \
                        --file-style="bold yellow ul" \
                        --hunk-header-style="omit" \
                        --paging=always
        else
            echo "⚠️  delta not installed — falling back to git diff + less" >&2
            echo "    install: brew install git-delta" >&2
            sleep 1
            git diff --color=always "$spec" | less -R
        fi
        ;;

    codediff)
        # VSCode-style two-tier (line + char) side-by-side, C-powered, moved-code detection
        echo "→ CodeDiff vs $TARGET" >&2
        exec env NVIM_APPNAME=LazyVIM nvim -c "CodeDiff $TARGET"
        ;;

    diffview)
        echo "→ DiffView vs $TARGET" >&2
        exec env NVIM_APPNAME=LazyVIM nvim -c "DiffviewOpen $TARGET"
        ;;

    delta)
        echo "→ delta side-by-side vs $TARGET" >&2
        if command -v delta >/dev/null 2>&1; then
            git -c delta.side-by-side=true -c delta.line-numbers=true diff "$TARGET" \
                | delta --paging=always
        else
            echo "⚠️  delta not installed — falling back to git diff + less" >&2
            echo "    install: brew install git-delta" >&2
            sleep 1
            git diff --color=always "$TARGET" | less -R
        fi
        ;;

    difftastic)
        echo "→ difftastic (semantic) vs $TARGET" >&2
        if command -v difft >/dev/null 2>&1; then
            GIT_EXTERNAL_DIFF=difft git diff "$TARGET" | less -R
        else
            echo "⚠️  difftastic not installed — falling back to git diff + less" >&2
            echo "    install: brew install difftastic" >&2
            sleep 1
            git diff --color=always "$TARGET" | less -R
        fi
        ;;

    files)
        echo "→ files changed vs $TARGET" >&2
        FILE=$(git diff --name-only "$TARGET" \
            | fzf --prompt='changed file: ' --height 50% --border \
                  --preview "git diff --color=always $TARGET -- {}")
        [[ -z "$FILE" ]] && { echo "no file picked" >&2; exit 0; }
        exec env NVIM_APPNAME=LazyVIM nvim -c "DiffviewOpen $TARGET -- $FILE"
        ;;

    *)
        echo "ERR: unknown tool '$TOOL'" >&2
        echo "valid: review | codediff | diffview | delta | difftastic | files" >&2
        exit 2
        ;;
esac
