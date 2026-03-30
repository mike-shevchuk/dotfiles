# Project Auto-Environment — activates tools on `cd` based on marker files in the directory
#
# Supported markers:
#   .venv/         → activate Python virtualenv (auto-deactivate when leaving)
#   .aws-profile   → set AWS_PROFILE from file contents
#   .docker-context→ switch docker context from file contents
#   .kube-context  → switch kubectl context from file contents

# Track the last auto-activated venv so we can deactivate when leaving
_PROJECT_ENV_VENV=""

_project_env_hook() {
    # --- Python venv ---
    if [ -d ".venv" ] && [ -f ".venv/bin/activate" ]; then
        # Only activate if we're not already in this venv
        if [[ "$_PROJECT_ENV_VENV" != "$PWD/.venv" ]]; then
            source ".venv/bin/activate"
            _PROJECT_ENV_VENV="$PWD/.venv"
        fi
    elif [[ -n "$_PROJECT_ENV_VENV" ]]; then
        # We left the venv directory — deactivate
        deactivate 2>/dev/null
        _PROJECT_ENV_VENV=""
    fi

    # --- AWS profile ---
    if [ -f ".aws-profile" ]; then
        export AWS_PROFILE="$(cat .aws-profile | tr -d '[:space:]')"
    fi

    # --- Docker context ---
    if [ -f ".docker-context" ]; then
        local ctx="$(cat .docker-context | tr -d '[:space:]')"
        docker context use "$ctx" >/dev/null 2>&1
    fi

    # --- Kubectl context ---
    if [ -f ".kube-context" ]; then
        local ctx="$(cat .kube-context | tr -d '[:space:]')"
        kubectl config use-context "$ctx" >/dev/null 2>&1
    fi
}

# Register the hook — runs on every directory change
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _project_env_hook
