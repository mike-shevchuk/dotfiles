---
description: "Bridge GSD's in-repo .planning/ knowledge into Mike's Obsidian second brain — sync curated LEARNINGS / milestone summaries / roadmap as tagged Obsidian notes (write), or surface relevant vault notes for planning context (read)"
argument-hint: "[sync | dry | context <keywords> | path]  (no args = dry preview first)"
---

# GSD ↔ Second Brain bridge

`.planning/` is GSD's ephemeral build scaffolding; `~/zettelkasten/claude_code/rescue-serverless/`
is the durable second brain. This command mirrors **only curated, useful knowledge**
(LEARNINGS = decisions/lessons/patterns/surprises, milestone summaries, roadmap) into
the vault as Obsidian notes (under the isolated `gsd/knowledge/<milestone>/<phase>/`)
with frontmatter + tags + wikilinks. Raw PLAN/SUMMARY/VERIFICATION scaffolding is
intentionally NOT synced. See design note
[[2026-06-16-gsd-pr-state-second-brain-design]] (Phase 2).

**Terminal language:** match Mike. **Run from a project root that has `.planning/`.**
Helper: `~/.codex/gsd-zettel-sync.sh` (sync|dry|context|path|help).

`$ARGUMENTS`

## Workflow

### Write (sync)

1. **Always dry-run first** unless Mike passed `sync` explicitly:
   ```bash
   ~/.codex/gsd-zettel-sync.sh dry
   ```
   Print the list of notes that WOULD be written (phase LEARNINGS, milestone
   summaries, roadmap) with their target vault paths + tags.
2. Show the preview, then on Mike's go (or if `$ARGUMENTS` already says `sync`):
   ```bash
   ~/.codex/gsd-zettel-sync.sh sync
   ```
   Each note gets Obsidian frontmatter (`tags`, `created`/`updated`,
   `gsd_source`, `gsd_milestone`, `gsd_phase`), a synced-from callout, the original
   GSD body (its own frontmatter stripped), and a `Related: [[MOC ...]]` backlink.
   Re-sync is idempotent and preserves the original `created` date.
3. **List the tags back in the terminal** (per Mike's zettelkasten rule) and the
   count of notes synced + the vault dir (`gsd-zettel-sync.sh path`).
4. Offer to add the synced notes to the vault MOC (don't edit user notes without asking).

### Read (context)

Surface relevant prior knowledge before planning a phase:
```bash
~/.codex/gsd-zettel-sync.sh context <keyword> [<keyword> ...]
```
Prints vault notes matching the keywords (rg/grep). Feed the hits into GSD
planning/research as context — this is the "read" half of the bidirectional bridge.

## Notes / rules

- **Curated, not mirror.** Only knowledge that can be reused later. No build scaffolding.
- **Vault override:** `GSD_ZETTEL_VAULT` env var (default
  `~/zettelkasten/claude_code/rescue-serverless`).
- **Manual now, hook later.** v1 is run-on-demand. A future GSD phase-boundary hook
  can auto-fire `sync` after `gsd-extract-learnings` / `gsd-complete-milestone`.
- Read-only on `.planning/` — the bridge never mutates GSD's working state.
