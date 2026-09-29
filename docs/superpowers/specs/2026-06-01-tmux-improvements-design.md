# tmux Improvements — Design Spec

**Date:** 2026-06-01
**Branch:** `worktree-tmux` (worktree at `.claude/worktrees/tmux`)
**Scope:** Performance, correctness, robust 2-row status, new fzf/justfile-driven popups, visual polish.

---

## 1. Goals

1. **Performance** — eliminate the ~10 `#(...)` subprocesses spawned per status redraw (several invoked twice), which cause lag/flicker.
2. **Correctness** — remove the fragile hard-coded alignment; remove dead code; make the worktree-branch config actually coherent.
3. **Robust 2-row status** — row 1 carries *useful* active-pane context (git / path / python) instead of decorative dots that depend on a 12-space hack (Variant C).
4. **New functionality** — fzf/justfile-driven popups that make the setup more intuitive.
5. **Visual polish** — consistent Catppuccin Mocha palette, readable tabs and borders.

## 2. Chosen Variants (from HTML mockups)

- **Status: Variant C** — two rows. Row 0 = session + tabs (left) and sysinfo (right). Row 1 = git branch + full path + python of the **active pane**, left-filled (no alignment hack).
- **Pane borders: P1 (full)** — each pane's border shows claude-state + uptime + path + git + python. (Row 1 duplicates the active pane's git/python prominently; acceptable and intentional — non-active panes still surface their own context via their border.)
- **Features (all four):** Switcher++ (`prefix Tab`), Claude dashboard (`prefix A`), just-menu (`prefix J`), worktree-session (`prefix W`), plus a hotkey cheat-sheet (`prefix ?`).

## 3. Architecture

### 3.1 Performance: user-options cache instead of inline `#(...)`

**Problem.** `status-right`, `status-format[1]`, and `pane-border-format` each embed multiple `#(~/.tmux-status.sh …)` calls. The `#{?#(cmd),…#(cmd)…}` idiom runs each command **twice** (`pane-git` and `pane-python` are each called twice in `pane-border-format`; `claude`/`python` twice in `status-right`). At `status-interval 10` that is a burst of git / mise / pyenv / pgrep / jq / vm_stat / kubectl subprocesses on every redraw.

**Solution.** Adopt the pattern the base gpakosz config already uses for `@battery_percentage`: a background updater computes values and stores them in **tmux user-options**; the format strings read `#{@cpu}` etc. with **zero subprocesses**.

- New segment **`refresh-global`** in `.tmux-status.sh`: computes `cpu`, `ram`, `claude`, `sessions` once and sets `@cpu`, `@ram`, `@claude`, `@sessions` via a single `tmux set -g …` batch.
- Driven by `status-interval` through one `#(…)` call that returns empty (side-effect only), or via a lightweight loop hook. Net: **one** subprocess per interval instead of ~10.
- Format strings reference `#{@cpu}`, `#{@ram}`, `#{@claude}`, `#{@sessions}`.

### 3.2 Active-pane segments (row 1): refresh via hooks

- New segment **`refresh-pane`** computes git (branch + worktree) and python for the active pane's cwd, sets `@pane_git`, `@pane_python`, `@pane_path`.
- Triggered by tmux hooks: `after-select-pane`, `pane-focus-in`, and `after-select-window`. These fire only on user navigation, not on every redraw.
- Row 1 (`status-format[1]`) reads `#{@pane_git}`, `#{@pane_path}`, `#{@pane_python}` — zero subprocesses.

### 3.3 Pane borders: single call, no double invocation

- New segment **`pane-meta <pane_id> <cwd>`** returns one pre-formatted string containing git + python (with the tmux colour escapes), so `pane-border-format` calls the script **once** per pane instead of the current `#{?#(git)…#(git)…#(py)…#(py)…}` (four calls).
- Border still renders only for visible panes, so cost is bounded.

### 3.4 New feature scripts

All live in `tmux/scripts/`, mirroring `git-compare.sh` (bash, `set -uo pipefail`, fzf with `--border`, graceful fallback). Bound via `display-popup -E`.

| Script | Binding | Behaviour |
|---|---|---|
| `session-switch.sh` | `prefix Tab` | fzf list of sessions; `--preview` shows windows/panes/git/claude count; Enter → `switch-client`. |
| `claude-dashboard.sh` | `prefix A` | Scans all panes across sessions where `pane_current_command == claude`; lists `sess:win.pane  state  uptime  path  branch`; Enter → `switch-client` + `select-window`/`select-pane`. |
| `just-menu.sh` | `prefix J` | Parses recipes from `~/dotfiles/justfile` (+ project `justfile` if present); fzf with recipe doc-comments as preview; Enter runs `just <recipe>` in the popup. |
| `worktree-session.sh` | `prefix W` | `git worktree list` of current repo → fzf → create/attach a tmux session rooted in that worktree (reuses the `ts` naming convention: basename, dots→underscores). |
| `keys-help.sh` | `prefix ?` | Renders a static, grouped cheat-sheet of all custom bindings in a scrollable popup. |

`prefix Tab` currently maps to `last-window` in the base config and `BTab` to `switch-client -l`. **Decision:** rebind `prefix Tab` to the switcher; move "last window" to remain on the base `Tab` only if unused — verify no conflict during implementation and pick a free key if `Tab` is load-bearing (fallback: `prefix S`).

### 3.5 Cleanup

- Delete the disabled "Duplicate popup section" comment block (lines ~155–163).
- Remove `status-format[1]` 12-space hack and the dots logic (superseded by Variant C).
- Keep `#!important` markers (gpakosz `_apply_configuration` requires them to override the base theme).

## 4. Data Flow

```
status-interval (10s) ──► .tmux-status.sh refresh-global ──► tmux set -g @cpu/@ram/@claude/@sessions
                                                                      │
pane focus / window change ──► .tmux-status.sh refresh-pane ──► @pane_git/@pane_python/@pane_path
                                                                      │
                                                                      ▼
status-left / status-right / status-format[1] read #{@…}  (no subprocess)
pane-border-format ──► .tmux-status.sh pane-meta <id> <cwd>  (1 call per visible pane)
```

## 5. Error Handling

- Every script segment exits 0 with empty output when data is unavailable (so `#{?…}` conditionals hide the segment). Existing pattern preserved.
- Feature scripts: missing tool (fzf/just/lazygit) → friendly message + `read -n1`, never a silent failure (matches `git-compare.sh`).
- `refresh-*` segments must be fast and never block; wrap external calls with `2>/dev/null` and short-circuit when cwd is missing/not a dir (already done for `pane-python`).
- Cross-platform: cpu/ram/uptime already branch on Linux/macOS; new code must keep `sh`-portable constructs (no bashisms in `.tmux-status.sh`, which is `#!/bin/sh`). Feature scripts under `scripts/` may be bash.

## 6. Testing

1. **Config loads:** `tmux -L spec-test -f tmux/.tmux.conf new-session -d` against the worktree files (symlink `~/.tmux-status.sh` to the worktree copy for the test, or invoke with an absolute path) → assert no parse errors, then `tmux -L spec-test kill-server`.
2. **Segments:** call each `.tmux-status.sh <segment>` directly and assert output shape (e.g. `cpu` numeric, `refresh-global` sets the options — verify with `tmux show -g @cpu`).
3. **Scripts:** `shellcheck` all of `tmux/scripts/*.sh`; smoke-run non-interactive paths (e.g. `just-menu.sh --list` prints recipes) where feasible.
4. **Visual:** manual check in a live session after `prefix r` reload — confirm row 1 shows active-pane git/path/python and updates on pane switch; confirm sysinfo no longer flickers.

## 7. Out of Scope (YAGNI)

- tmux-resurrect / continuum (kept disabled per current config).
- Powerline status (Variant D rejected — Nerd Font dependency).
- Reworking the gpakosz base `.tmux.conf` (upstream "DO NOT EDIT" file).

## 8. Files Touched

- `tmux/.tmux.conf.local` — status C, border P1, new bindings, cleanup.
- `tmux/.tmux-status.sh` — `refresh-global`, `refresh-pane`, `pane-meta` segments.
- `tmux/scripts/session-switch.sh`, `claude-dashboard.sh`, `just-menu.sh`, `worktree-session.sh`, `keys-help.sh` — new.
- `docs/superpowers/specs/2026-06-01-tmux-improvements-design.md` — this spec.

## 9. Deliverable

A PR from `worktree-tmux` (or a fresh feature branch off it) → `master`, with the above changes, a clear description, and the mockup decisions recorded.
