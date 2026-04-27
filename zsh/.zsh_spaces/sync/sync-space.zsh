# sync-space.zsh — opt-in background `git pull --rebase --autostash` for
#                    ~/dotfiles and ~/zettelkasten on shell startup.
#
# OFF by default to keep new shells fast and silent. Enable in ~/.zshrc:
#
#     export DOTFILES_AUTO_PULL=1
#
# When enabled, each new interactive shell forks a background pull for
# every repo in $DOTFILES_AUTO_PULL_REPOS (defaults to dotfiles + zettelkasten).
# Pulls only — never pushes. Output is suppressed; rebase conflicts are
# handled by --autostash so they leave the working tree clean and just
# stop. Run `just sync` manually to see what happened.
#
# To disable for a single shell, prefix:  DOTFILES_AUTO_PULL=0 zsh

[[ -n "${DOTFILES_AUTO_PULL:-}" ]] && [[ "$DOTFILES_AUTO_PULL" != "0" ]] && {
    : "${DOTFILES_AUTO_PULL_REPOS:=$HOME/dotfiles $HOME/zettelkasten}"
    for _repo in ${=DOTFILES_AUTO_PULL_REPOS}; do
        [[ -d "$_repo/.git" ]] || continue
        (cd "$_repo" && git pull --rebase --autostash --quiet >/dev/null 2>&1 &) >/dev/null 2>&1
    done
    unset _repo
}
