# Codex configuration diagnostics

# Show migrated hooks, skills, prompts, and active footer configuration
codex-status:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{justfile_directory()}}/codex/.codex"
    printf "Codex package: %s\n" "$root"
    printf "  skills:  %s\n" "$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    printf "  prompts: %s\n" "$(find "$root/prompts" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
    printf "  hooks:   %s\n" "$(jq -r '.hooks | keys | join(", ")' "$root/hooks.json")"
    printf "  footer:  %s\n" "$(awk -F'= ' '/^status_line =/{print $2}' "$root/config.toml")"
    if [ -L "$HOME/.codex/config.toml" ]; then
        printf "  stow:    linked\n"
    else
        printf "  stow:    not linked — run: just codex\n"
    fi

# Find user-level Codex customization files not managed by this package
codex-drift:
    #!/usr/bin/env bash
    set -euo pipefail
    managed="{{justfile_directory()}}/codex/.codex"
    [ -d "$HOME/.codex" ] || exit 0
    find "$HOME/.codex" -maxdepth 3 -type f \
      \( -path '*/hooks/*' -o -path '*/prompts/*' -o -path '*/skills/*' -o -name 'hooks.json' -o -name 'config.toml' \) \
      -print | while read -r file; do
        [ -L "$file" ] && continue
        rel="${file#"$HOME/.codex/"}"
        [ -e "$managed/$rel" ] || printf "not in repo: ~/.codex/%s\n" "$rel"
      done

# Validate Codex config, hooks, skills, and migrated Python tooling
codex-test:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{justfile_directory()}}/codex/.codex"
    jq empty "$root/hooks.json"
    python3 -c 'import pathlib,sys,tomllib; root=pathlib.Path(sys.argv[1]); tomllib.loads((root/"config.toml").read_text()); [compile(p.read_text(), str(p), "exec") for p in root.rglob("*.py")]' "$root"
    ruby -e 'require "yaml"; Dir[ARGV[0]+"/skills/*/SKILL.md"].each { |f| m=YAML.safe_load(File.read(f).split(/^---\s*$\n/)[1]); abort("invalid skill: #{f}") unless m.keys.sort == ["description", "name"] && m["name"] == File.basename(File.dirname(f)) }' "$root"
    printf "Codex package validation passed\n"
