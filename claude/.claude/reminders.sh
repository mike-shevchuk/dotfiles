#!/usr/bin/env bash
# reminders.sh — tiny persistent reminder store surfaced in the statusline.
# One markdown file per reminder in ~/.claude/reminders/, frontmatter:
#   title:  short label (shown in statusline + list)
#   status: active | done  (only 'active' counts toward the 🔔 badge)
# Body = free text (commands, notes).
#
#   reminders.sh count                 -> number of active reminders
#   reminders.sh badge                 -> "🔔N label" text for the statusline (empty if 0)
#   reminders.sh list                  -> active reminders (slug + title)
#   reminders.sh list all              -> include done
#   reminders.sh show <slug>           -> print one reminder's body
#   reminders.sh done <slug>           -> mark done (drops off the badge)
#   reminders.sh reopen <slug>         -> mark active again
#   reminders.sh add <slug> <title>    -> create from stdin body
#   reminders.sh path                  -> print the store dir
set -euo pipefail
DIR="${REMINDERS_DIR:-$HOME/.claude/reminders}"
mkdir -p "$DIR"

_field() { sed -n "s/^$2:[[:space:]]*//p" "$1" 2>/dev/null | head -1; }
_status() { local s; s=$(_field "$1" status); echo "${s:-active}"; }
_title()  { local t; t=$(_field "$1" title); echo "${t:-$(basename "$1" .md)}"; }

_active_files() {
  local f
  for f in "$DIR"/*.md; do
    [ -e "$f" ] || continue
    [ "$(_status "$f")" = "active" ] && echo "$f"
  done
}

cmd="${1:-list}"; shift || true
case "$cmd" in
  count)
    _active_files | grep -c '' || true
    ;;
  badge)
    n=$(_active_files | grep -c '' || true)
    [ "$n" -eq 0 ] && exit 0
    first=$(_active_files | head -1 || true)   # head closes the pipe early; don't let SIGPIPE+pipefail abort with >=2 reminders
    printf '🔔%s %s' "$n" "$(_title "$first")"
    ;;
  list)
    incl="${1:-active}"
    for f in "$DIR"/*.md; do
      [ -e "$f" ] || continue
      st=$(_status "$f")
      { [ "$incl" = "all" ] || [ "$st" = "active" ]; } || continue
      printf '%-32s [%s] %s\n' "$(basename "$f" .md)" "$st" "$(_title "$f")"
    done
    ;;
  show)
    f="$DIR/${1:?slug required}.md"; [ -f "$f" ] || { echo "no such reminder: $1" >&2; exit 1; }
    cat "$f"
    ;;
  done|reopen)
    new=$([ "$cmd" = "done" ] && echo done || echo active)
    f="$DIR/${1:?slug required}.md"; [ -f "$f" ] || { echo "no such reminder: $1" >&2; exit 1; }
    if grep -q '^status:' "$f"; then
      sed -i '' "s/^status:.*/status: $new/" "$f"
    else
      sed -i '' "1a\\
status: $new
" "$f"
    fi
    echo "✓ $1 -> $new"
    ;;
  add)
    slug="${1:?slug required}"; shift; title="${*:-$slug}"
    f="$DIR/$slug.md"
    { printf -- '---\ntitle: %s\nstatus: active\ncreated: %s\n---\n' "$title" "$(date +%Y-%m-%d)"; cat; } > "$f"
    echo "✓ added $slug"
    ;;
  path) echo "$DIR" ;;
  *) echo "usage: reminders.sh {count|badge|list [all]|show <slug>|done <slug>|reopen <slug>|add <slug> <title>|path}" >&2; exit 2 ;;
esac
