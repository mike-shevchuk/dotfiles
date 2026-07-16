#!/usr/bin/env bash
# git-compare.sh — open a diff between current branch and a target branch.
# Used by tmux popup bindings (prefix V/M/N/O).
#
# EVERY mode prompts for the target branch via fzf. Default branch is pre-selected
# (cursor on first line) so you can just hit Enter for the common case.
#
# Tools (1st arg):
#   menu         — pick a PLATFORM (codediff/diffview/delta/difftastic/tig) via fzf,
#                  THEN HEAD+BASE two-picker, then launch the chosen viewer. (prefix C-v)
#   review       — GitHub-PR-style unified diff via delta; pick HEAD (default current)
#                  + BASE (default origin's main/master) branches, diff BASE→HEAD
#   codediff     — VSCode-style two-tier diff (line + char), C-powered, moved-code
#                  detection. HEAD+BASE two-picker, PR-style. (prefix V)
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

# ─── List branches, hiding remote twins of local ones ──────────────────────
# `git branch -a` shows both `foo` and `origin/foo`; the twin is noise in a
# picker. Keep origin/* only when no local branch of the same name exists.
list_branches() {
    git branch -a --format='%(refname:short)' | grep -v '^HEAD' \
        | awk '{ n=$0; sub(/^origin\//, "", n);
                 if ($0 == n) { local[n]=1; print }        # local branch
                 else remote[n]=$0 }                        # origin/<n>
               END { for (n in remote) if (!(n in local)) print remote[n] }' \
        | sort -u
}

# ─── fzf branch picker (default branch first → cursor lands on it) ─────────
pick_branch() {
    local current default
    current=$(git branch --show-current 2>/dev/null)
    default=$(detect_default_branch || true)

    {
        # Default branch first — cursor lands on line 1, just hit Enter for common case
        [[ -n "$default" ]] && echo "$default"
        # Then everything else (sorted, dedupe, exclude current branch + default).
        # -Fx = fixed-string exact match: branch names like fix.v2 are not regexes.
        list_branches \
            | grep -vFx "$current" \
            | grep -vFx "$default"
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
        list_branches | grep -vFx "$def"
    } | fzf --prompt="$prompt" --height 60% --border \
            --preview 'git log --oneline -10 {}' --preview-window 'right:50%'
}

# ─── Two-picker HEAD/BASE flow (shared by codediff + menu) ─────────────────
# Sets globals CUR_REF, HEAD_REF, BASE_REF (same UX as review's two pickers).
pick_head_base() {
    CUR_REF=$(git branch --show-current 2>/dev/null)
    local base_def
    base_def=$(detect_default_branch || echo "origin/master")
    HEAD_REF=$(pick_branch_default "$CUR_REF" "head — review THIS branch (Enter=current): ")
    [[ -z "$HEAD_REF" ]] && { echo "no head branch picked — aborted" >&2; exit 0; }
    BASE_REF=$(pick_branch_default "$base_def" "base — compare against (Enter=$base_def): ")
    [[ -z "$BASE_REF" ]] && { echo "no base branch picked — aborted" >&2; exit 0; }
}

# ─── Resolve PR-direction spec: LEFT=merge-base, RIGHT=HEAD tip or "" (working) ─
compute_pr_spec() {
    LEFT=$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null || echo "$BASE_REF")
    if [[ "$HEAD_REF" == "$CUR_REF" ]]; then RIGHT=""; else RIGHT="$HEAD_REF"; fi
}

# ─── Launch one diff viewer for the resolved LEFT→RIGHT spec ────────────────
# RIGHT empty means "working tree". Add a case + a menu line to offer more tools.
launch_view() {
    local tool="$1"
    echo "→ ${tool} (PR): ${BASE_REF} → ${HEAD_REF} [${RIGHT:-working tree}]" >&2
    case "$tool" in
        codediff)
            exec env NVIM_APPNAME=LazyVIM nvim -c "CodeDiff ${LEFT} ${RIGHT}"
            ;;
        diffview)
            local spec="$LEFT"
            [[ -n "$RIGHT" ]] && spec="${LEFT}..${RIGHT}"
            exec env NVIM_APPNAME=LazyVIM nvim -c "DiffviewOpen ${spec}"
            ;;
        delta)
            if command -v delta >/dev/null 2>&1; then
                git -c delta.side-by-side=true -c delta.line-numbers=true \
                    diff "$LEFT" ${RIGHT:+"$RIGHT"} | delta --paging=always
            else
                echo "⚠️  delta not installed — brew install git-delta" >&2; sleep 1
                git diff --color=always "$LEFT" ${RIGHT:+"$RIGHT"} | less -R
            fi
            ;;
        difftastic)
            if command -v difft >/dev/null 2>&1; then
                GIT_EXTERNAL_DIFF=difft git diff "$LEFT" ${RIGHT:+"$RIGHT"} | less -R
            else
                echo "⚠️  difftastic not installed — brew install difftastic" >&2; sleep 1
                git diff --color=always "$LEFT" ${RIGHT:+"$RIGHT"} | less -R
            fi
            ;;
        tig)
            if command -v tig >/dev/null 2>&1; then
                exec tig "${LEFT}..${RIGHT:-HEAD}"
            else
                echo "⚠️  tig not installed — brew install tig" >&2; sleep 1
                git diff --color=always "$LEFT" ${RIGHT:+"$RIGHT"} | less -R
            fi
            ;;
        *)
            echo "ERR: unknown view tool '$tool'" >&2; exit 2
            ;;
    esac
}

# ─── Pick target branch ────────────────────────────────────────────────────
# review + codediff + menu + diffview pick their OWN refs (custom pickers);
# the other modes compare the working tree against a single picked branch.
if [[ "$TOOL" != "review" && "$TOOL" != "codediff" && "$TOOL" != "menu" && "$TOOL" != "diffview" && "$TOOL" != "help" ]]; then
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
            # Current branch as HEAD. A dirty working tree can DROWN the real
            # branch diff in unrelated uncommitted noise (e.g. a stray yarn.lock),
            # so when dirty, ask which scope to show — Enter = clean committed
            # PR view (what GitHub shows), "working" = include uncommitted edits.
            scope="committed"
            if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
                scope=$(printf '%s\n' \
                    "committed — only commits on the branch (clean PR view, like GitHub)" \
                    "working   — include uncommitted working-tree edits" \
                    | fzf --prompt='diff scope (Enter=committed): ' --height 40% --border \
                    | awk '{print $1}')
                [[ -z "$scope" ]] && { echo "no scope picked — aborted" >&2; exit 0; }
            fi
            if [[ "$scope" == "working" ]]; then
                spec=$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo "$BASE_REF")
            else
                spec="$BASE_REF...HEAD"
            fi
        else
            scope="committed"
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
        echo "→ PR diff: $BASE_REF → $HEAD_REF [$scope]" >&2
        # Banner INSIDE the paged stream — so it's visible at the top of the
        # pager and you always see WHAT is being compared (stderr scrolls away).
        banner=$(printf '━━━ PR: %s → %s   [scope: %s] ━━━' "$BASE_REF" "$HEAD_REF" "$scope")
        if command -v delta >/dev/null 2>&1; then
            { echo "$banner"; echo; git diff "$spec"; } \
                | delta --line-numbers \
                        --file-style="bold yellow ul" \
                        --hunk-header-style="omit" \
                        --paging=always
        else
            echo "⚠️  delta not installed — falling back to git diff + less" >&2
            echo "    install: brew install git-delta" >&2
            sleep 1
            { echo "$banner"; echo; git diff --color=always "$spec"; } | less -R
        fi
        ;;

    codediff)
        # VSCode-style two-tier diff with the SAME two-picker UX as review:
        # pick HEAD (default current) + BASE (default origin's default), diff
        # BASE→HEAD. If HEAD is the current branch, the right side is the WORKING
        # TREE; otherwise the committed 3-dot diff. (shared helpers above)
        pick_head_base
        compute_pr_spec
        launch_view codediff
        ;;

    menu)
        # Pick a PLATFORM first, then the same HEAD/BASE two-picker, then launch
        # the chosen viewer — run the SAME comparison through different tools to
        # find the one you like best. Add a line here + a launch_view() case for more.
        PLATFORM=$(printf '%s\n' \
            "codediff    VSCode-style two-tier (line+char), moved-code detection [nvim]" \
            "diffview    side-by-side file list + scrollable diff [nvim]" \
            "delta       side-by-side pager, syntax-highlighted [terminal]" \
            "difftastic  semantic / AST-aware structural diff [terminal]" \
            "tig         TUI commit + diff browser [terminal · brew install tig]" \
            | fzf --prompt='diff platform (Enter=codediff): ' --height 60% --border \
                  --header='choose how to view  BASE → HEAD' \
            | awk '{print $1}')
        [[ -z "$PLATFORM" ]] && { echo "no platform picked — aborted" >&2; exit 0; }
        pick_head_base
        compute_pr_spec
        launch_view "$PLATFORM"
        ;;

    diffview)
        # prefix v. ONE fzf picker (default origin/main → origin/master). Keys are
        # shown in the fzf header:
        #   Enter  → your branch vs base: committed <base>...HEAD (3-dot, PR view);
        #            if nothing is committed yet, falls back to the working-tree
        #            diff vs base (so you never get an empty view).
        #   Tab    → pick a 2nd branch (head), 3-dot <base>...<head> — changes
        #            since the merge-base (GitHub "Files changed").
        #   Ctrl-T → pick a 2nd branch (head), 2-dot <base>..<head> — the EXACT
        #            difference between the two tips. Stable when 3-dot is ambiguous
        #            (multiple merge-bases). "T" = two-dot.
        #   Ctrl-O → ALL uncommitted changes: working tree vs HEAD incl. untracked.
        #            (Ctrl-A can't be used — it's a tmux prefix here. gitignored
        #            files are never shown — DiffView has no support for them.)
        # The compared refs + dot-mode are shown in nvim on open (notify + panel).
        cur=$(git branch --show-current 2>/dev/null)
        # Default (first line): detect_default_branch already prefers
        # origin/HEAD → origin/main → origin/master (single source of truth).
        base_def=$(detect_default_branch || echo "origin/master")
        dv_out=$(
            {
                echo "$base_def"
                list_branches | grep -vFx "$base_def"
            } | fzf --prompt="DiffView vs (Enter=$base_def): " \
                    --header=$'Enter → branch vs base (3-dot)   Tab → 2nd branch (3-dot/PR)   Ctrl-T → 2nd branch (2-dot/exact)   Ctrl-O → all uncommitted   Ctrl-L → + LGTM findings (quickfix)' \
                    --expect=tab,ctrl-t,ctrl-o,ctrl-l \
                    --height 60% --border \
                    --preview 'git log --oneline -10 {}' --preview-window 'right:50%'
        )
        dv_key=$(printf '%s\n' "$dv_out" | sed -n 1p)
        dv_base=$(printf '%s\n' "$dv_out" | sed -n 2p)

        # Picking your CURRENT branch means "review MY branch" — a branch vs
        # itself is always empty and used to fall back to a confusing
        # working-tree-only diff. Remap it to: default base → current branch.
        # (Not for Tab/Ctrl-T — there the pick is a base for a 2nd-branch flow.)
        if [[ -n "$dv_base" && "$dv_base" == "$cur" && "$dv_key" != "tab" && "$dv_key" != "ctrl-t" ]]; then
            echo "→ '$cur' is the current branch — comparing $base_def → $cur instead" >&2
            dv_base="$base_def"
        fi

        # Open DiffView and announce the compared refs inside nvim (a notify toast
        # + the panel's own "Showing changes for:" line), so it's always clear what
        # is being compared.  $1 = DiffviewOpen args, $2 = human label.
        dv_open() {
            echo "→ DiffView: $2" >&2
            # escape single quotes for the lua string (branch names can carry them)
            local label="${2//\'/\\\'}"
            exec env NVIM_APPNAME=LazyVIM nvim \
                -c "DiffviewOpen $1" \
                -c "lua vim.defer_fn(function() pcall(vim.notify, 'Comparing: $label', vim.log.levels.INFO, { title = 'DiffView' }) end, 250)"
        }

        # Ctrl-L: same as Enter, but LGTM findings ride along as a quickfix list —
        # j/k through review findings INSIDE the diff (design.md §9, plugin-free).
        # Uses the newest .lgtm/reviews/*/findings.json; :copen is pre-executed.
        dv_open_lgtm() {
            local spec="$1" label="$2"
            local repo qf newest
            repo=$(git rev-parse --show-toplevel)
            newest=$(ls -td "$repo"/.lgtm/reviews/*/ 2>/dev/null | head -1)
            if [[ -z "$newest" || ! -f "$newest/findings.json" ]]; then
                echo "⚠️  немає findings.json під .lgtm/reviews/ — спершу: jb2b review …" >&2
                sleep 2
                dv_open "$spec" "$label"
                return
            fi
            qf=$(mktemp /tmp/lgtm-qf.XXXXXX)
            python3 - "$newest/findings.json" > "$qf" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for f in doc.get("findings", []):
    prob = (f.get("problem") or {})
    txt = prob.get("ukr") or prob.get("eng") or f.get("id", "")
    sev = f"{f.get('severity_emoji','')} {f.get('severity_score','')}/100"
    print(f"{f['file']}:{f['line']}: {sev} {txt}")
PY
            echo "→ DiffView + LGTM quickfix: $(basename "$newest") ($(wc -l < "$qf" | tr -d ' ') знахідок)" >&2
            local label2="${label//\'/\\\'}"
            exec env NVIM_APPNAME=LazyVIM nvim -q "$qf" \
                -c "DiffviewOpen $spec" -c "copen 8" \
                -c "lua vim.defer_fn(function() pcall(vim.notify, 'Comparing: $label2 + LGTM findings (:cnext/:cprev)', vim.log.levels.INFO, { title = 'DiffView' }) end, 250)"
        }

        case "$dv_key" in
            ctrl-o)
                dv_open "--untracked-files=true" "working tree → HEAD  (all uncommitted, +untracked)"
                ;;
            ctrl-l)
                [[ -z "$dv_base" ]] && { echo "no branch picked — aborted" >&2; exit 0; }
                if git diff --quiet "$dv_base...HEAD" 2>/dev/null; then
                    dv_open_lgtm "$dv_base" "working tree → $dv_base + findings"
                else
                    dv_open_lgtm "$dv_base...HEAD" "3-dot  $dv_base...${cur:-HEAD} + findings"
                fi
                ;;
            tab|ctrl-t)
                [[ -z "$dv_base" ]] && { echo "no base picked — aborted" >&2; exit 0; }
                dv_head=$(pick_branch_default "$cur" "DiffView head — $dv_base → (Enter=$cur): ")
                [[ -z "$dv_head" ]] && { echo "no head picked — aborted" >&2; exit 0; }
                if [[ "$dv_key" == "ctrl-t" ]]; then
                    dv_open "$dv_base..$dv_head"  "2-dot  $dv_base..$dv_head  (exact difference between tips)"
                else
                    dv_open "$dv_base...$dv_head" "3-dot  $dv_base...$dv_head  (changes since merge-base / PR)"
                fi
                ;;
            *)
                [[ -z "$dv_base" ]] && { echo "no branch picked — aborted" >&2; exit 0; }
                if git diff --quiet "$dv_base...HEAD" 2>/dev/null; then
                    # Nothing committed vs base → show the working tree instead of an
                    # empty DiffView.
                    dv_open "$dv_base" "working tree → $dv_base  (no committed diff)"
                else
                    dv_open "$dv_base...HEAD" "3-dot  $dv_base...${cur:-HEAD}  (committed / PR)"
                fi
                ;;
        esac
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
                  --preview "git diff --color=always '$TARGET' -- {}")
        [[ -z "$FILE" ]] && { echo "no file picked" >&2; exit 0; }
        # quoted path in the ex command — filenames with spaces must not split
        exec env NVIM_APPNAME=LazyVIM nvim -c "DiffviewOpen $TARGET -- '$FILE'"
        ;;

    help)
        cat >&2 <<'EOF'
git-compare.sh — diff viewers behind tmux bindings

  prefix v    diffview   DiffView side-by-side; fzf keys:
                           Enter  → branch vs base (3-dot; порожній → working tree)
                           Tab    → 2nd branch, 3-dot (PR view)
                           Ctrl-T → 2nd branch, 2-dot (exact tips)
                           Ctrl-O → all uncommitted (+untracked)
                           Ctrl-L → + LGTM findings як quickfix (:cnext/:cprev)
  prefix V    codediff   VSCode-style two-tier diff (line+char)
  prefix C-v  menu       спершу платформа (codediff/diffview/delta/difftastic/tig)
              review     GitHub-PR-style unified delta
              delta/difftastic/files — разові режими

  usage: git-compare.sh <menu|review|codediff|diffview|delta|difftastic|files|help>
EOF
        ;;

    *)
        echo "ERR: unknown tool '$TOOL'" >&2
        echo "valid: menu | review | codediff | diffview | delta | difftastic | files | help" >&2
        exit 2
        ;;
esac
