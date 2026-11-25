# --- venv — pyenv-virtualenv-style commands on top of uv -----------------------
#
# WHY — pyenv-virtualenv copies every package into every env (pip); uv clones from
# one cache (APFS clonefile), so shared packages cost ~0 extra disk and install 10-100x faster.
# Envs live centrally in ~/.venvs/<name> (not in project dirs); Python comes from pyenv
# (no uv downloads). A project points at an env with a `.venv` symlink → the existing
# chpwd hook (zsh/.zsh_spaces/job/project-env.zsh) auto-activates it, and uv / IDEs /
# Claude find it too.
#
#   pyenv-virtualenv                 just -g
#   pyenv virtualenv 3.12 reels   →  venv-new reels [3.12]
#   pyenv virtualenvs             →  venv-ls
#   pyenv local reels             →  venv-use reels        (.venv → ~/.venvs/reels in cwd)
#   pip install X                 →  venv-pip install X    (env of cwd; or uv pip … directly)
#   pyenv uninstall reels         →  venv-rm reels
#   (none)                        →  venv-migrate <pyenv-env> [name]   pip freeze → new uv env

venvs := home_directory() / ".venvs"

# Create ~/.venvs/<name> on a pyenv Python (default 3.14 = latest installed 3.14.x; poker stays 3.12 — coremltools has no cp314 wheel)
[group('venv')]
[no-cd]
venv-new name py="3.14":
    #!/usr/bin/env bash
    set -euo pipefail
    bin="$(pyenv prefix "{{py}}")/bin/python"
    [ -e "{{venvs}}/{{name}}" ] && { echo "  FAIL: {{venvs}}/{{name}} already exists" >&2; exit 1; }
    echo "━━━ uv ━━━  UV_PYTHON_DOWNLOADS=never uv venv {{venvs}}/{{name}} --python $bin" >&2
    UV_PYTHON_DOWNLOADS=never uv venv "{{venvs}}/{{name}}" --python "$bin" -q
    echo "  OK → {{venvs}}/{{name}} ($("{{venvs}}/{{name}}/bin/python" -V))   next: just -g venv-use {{name}}" >&2

# List envs in ~/.venvs: name, python, package count (● = active)
[group('venv')]
venv-ls:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ {{venvs}}" >&2
    for d in "{{venvs}}"/*/; do
      d=${d%/}; [ -x "$d/bin/python" ] || continue
      n=$(uv pip list --python "$d/bin/python" 2>/dev/null | tail -n +3 | wc -l | tr -d ' ')
      mark=" "; [ "${VIRTUAL_ENV:-}" = "$d" ] && mark="●"
      printf "%s %-18s %-14s %4s pkgs\n" "$mark" "$(basename "$d")" "$("$d/bin/python" -V 2>&1)" "$n"
    done

# Link cwd to an env (like `pyenv local`): .venv → ~/.venvs/<name>; cd . to activate
[group('venv')]
[no-cd]
venv-use name:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -x "{{venvs}}/{{name}}/bin/python" ] || { echo "  FAIL: no env {{name}} (just -g venv-ls)" >&2; exit 1; }
    if [ -e .venv ] && [ ! -L .venv ]; then echo "  FAIL: $PWD/.venv is a real dir, not touching it" >&2; exit 1; fi
    echo "→ ln -sfn {{venvs}}/{{name}} $PWD/.venv" >&2
    ln -sfn "{{venvs}}/{{name}}" .venv
    git check-ignore -q .venv 2>/dev/null || { git rev-parse 2>/dev/null && echo "  hint: add .venv to .gitignore" >&2; } || true
    echo "  OK — run 'cd .' to activate in this shell" >&2

# uv pip in the env of cwd (.venv link) or $VIRTUAL_ENV: just -g venv-pip install numpy
[group('venv')]
[no-cd]
venv-pip +args:
    #!/usr/bin/env bash
    set -euo pipefail
    env="${VIRTUAL_ENV:-}"; [ -e .venv ] && env="$(cd .venv && pwd -P)"
    [ -n "$env" ] || { echo "  FAIL: no .venv here and no active env" >&2; exit 1; }
    echo "━━━ uv ━━━  uv pip {{args}} --python $env/bin/python" >&2
    uv pip {{args}} --python "$env/bin/python"

# Delete ~/.venvs/<name> (asks first; packages stay in uv cache until `uv cache prune`)
[group('venv')]
venv-rm name:
    #!/usr/bin/env bash
    set -euo pipefail
    d="{{venvs}}/{{name}}"; [ -d "$d" ] || { echo "  FAIL: no env {{name}}" >&2; exit 1; }
    echo "→ $d ($(du -sh "$d" | cut -f1) apparent)" >&2
    gum confirm "Delete env {{name}}?" </dev/tty || { echo "  aborted" >&2; exit 0; }
    rm -rf "$d"; echo "  OK — dangling .venv links in projects now point nowhere" >&2

# Move a pyenv-virtualenv env to uv: same Python, same packages (pip freeze). Old env is kept.
[group('venv')]
venv-migrate env name="":
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{name}}"; [ -n "$name" ] || name="{{env}}"
    old="$(cd "$(pyenv prefix "{{env}}")" && pwd -P)"; py=$(basename "$(dirname "$(dirname "$old")")")   # real path …/versions/3.12.11/envs/<env>
    echo "[1/3] pip freeze {{env}} ($py)..." >&2
    req=$(mktemp); "$old/bin/python" -m pip freeze --exclude-editable > "$req"; echo "  $(wc -l < "$req" | tr -d ' ') pkgs" >&2
    echo "[2/3] ━━━ just ━━━  just -g venv-new $name $py" >&2
    just -g venv-new "$name" "$py"
    echo "[3/3] ━━━ uv ━━━  uv pip install --python {{venvs}}/$name/bin/python -r $req" >&2
    uv pip install --python "{{venvs}}/$name/bin/python" -r "$req" -q
    rm -f "$req"; echo "  OK — check it, then: pyenv uninstall {{env}}" >&2
