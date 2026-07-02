# ~/.zshenv — sourced by ALL zsh instances (interactive, scripts, ssh, cron).
# UTF-8 everywhere: without this, non-GUI shells (ssh-in sessions, tmux server
# started at boot, cron) run in the C locale → mojibake, broken glyphs, tools
# mangling Cyrillic filenames. macOS ssh/sshd already forward LANG/LC_* both
# ways (SendEnv/AcceptEnv in /etc/ssh/*_config.d/100-macos.conf) — there just
# has to be a locale to send.
# Don't clobber a locale the SSH client already sent us.
if [[ -z "${LANG:-}" || "${LANG}" == "C" || "${LANG}" == "POSIX" ]]; then
    export LANG='en_US.UTF-8'
fi
export LC_CTYPE='en_US.UTF-8'
# Deliberately NOT setting LC_ALL — it's a sledgehammer that breaks per-category overrides.
