#!/usr/bin/env bash
# git-compare.sh — open a diff between current branch and a target branch.
# Used by tmux popup bindings (prefix V/M/N/O).
#
# EVERY mode prompts for the target branch via fzf. Default branch is pre-selected
# (cursor on first line) so you can just hit Enter for the common case.
#
# Tools (1st arg):
#   review       — GitHub-PR-style unified diff via delta; auto: current branch vs
#                  default base (main/master), NO branch picker (PR head→base direction)
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

# ─── Pick target branch ──────────────────────────────────────────────────
# review = "GitHub PR review of THIS branch": auto-target the default base
# (main/master) with NO picker — head is your current branch, base is main,
# exactly like a PR. The other modes prompt for any branch via fzf.
if [[ "$TOOL" == "review" ]]; then
    TARGET=$(detect_default_branch || true)
    [[ -z "$TARGET" ]] && TARGET=$(pick_branch)   # fallback if no default detected
else
    TARGET=$(pick_branch)
fi
if [[ -z "$TARGET" ]]; then
    echo "no branch picked — aborted" >&2
    exit 0
fi

# ─── Tool dispatch ──────────────────────────────────────────────────────────
case "$TOOL" in
    review)
        # GitHub-PR-style unified diff: single column with dual line numbers (old|new),
        # additions in green, deletions in red, file headers between sections.
        #
        # Diffs from the MERGE-BASE with $TARGET to the WORKING TREE — i.e.
        # everything this branch has changed since it diverged from $TARGET,
        # including uncommitted edits. So it:
        #   • matches GitHub's "Files changed" for committed work (merge-base,
        #     not two-dot → $TARGET's own newer commits aren't shown as deletions);
        #   • ALSO previews uncommitted changes, so it isn't empty when you're
        #     mid-work or sitting on an up-to-date branch (e.g. master).
        # (For a clean, fully-committed branch this is identical to GitHub.)
        BASE=$(git merge-base "$TARGET" HEAD 2>/dev/null || echo "$TARGET")
        # Empty diff → say so clearly instead of opening a blank pager (which
        # looks broken). Happens when this repo has no changes vs $TARGET, e.g.
        # an up-to-date/clean branch, or the popup opened in the wrong repo.
        if git diff --quiet "$BASE" 2>/dev/null; then
            printf '\033[1;33m✓ Nothing to review.\033[0m\n\n' >&2
            printf '  No changes between \033[1m%s\033[0m (merge-base) and your working tree.\n' "$TARGET" >&2
            printf '  repo: \033[36m%s\033[0m\n' "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" >&2
            printf '  branch: \033[36m%s\033[0m\n\n' "$(git branch --show-current 2>/dev/null || echo '(detached)')" >&2
            printf '  This popup diffs the CURRENT pane'\''s repo vs the picked branch.\n' >&2
            printf '  Run it from a repo/branch that has commits or edits not in %s.\n\n' "$TARGET" >&2
            printf '  press any key…' >&2
            read -n1 -rs _ 2>/dev/null || true
            exit 0
        fi
        echo "→ PR-style diff since merge-base with $TARGET" >&2
        if command -v delta >/dev/null 2>&1; then
            git diff "$BASE" \
                | delta --line-numbers \
                        --file-style="bold yellow ul" \
                        --hunk-header-style="omit" \
                        --paging=always
        else
            echo "⚠️  delta not installed — falling back to git diff + less" >&2
            echo "    install: brew install git-delta" >&2
            sleep 1
            git diff --color=always "$BASE" | less -R
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
