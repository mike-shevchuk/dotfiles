---
status: Draft
owner: "Mike Shevchuk"
updated_at: "2026-11-04"
depth: "medium"
---

# Idea brief — pipeline-state

## 1. Raw idea

запускай sdd process думаю треба покращити наш pr-state або зробити нову команду щось схоже на superpowers sdd speck kit bmat wayfind та інше що порадиш?

## 2. Problem

_Pending — being settled in the interview._

## 3. Users

_Pending._

## 4. Why now

_Pending._

## 5. Out of scope

- Adopting an external framework (spec-kit, BMAD, superpowers, wayfind) wholesale — owner-reported 2026-11-04: «хочу створити свій але запозичивши ідеї для правильного контролю та архітектури».
- Owner-required constraint: the UX is built on the owner's terminal tools — `just`, `fzf`, `gum`, `glow` «та інше» (owner-reported 2026-11-04; all four installed under /opt/homebrew/bin, source-verified 2026-11-04).
- Owner-required: `tiki` (github.com/boolean-maybe/tiki) as the markdown control surface — for mods/agents, for showing Mike a plan, and for the context description in `/mine-grill` (owner-reported 2026-11-04). tiki 0.6.1 is installed (source-verified 2026-11-04).

## 6. Risks

| claim/question | class | source/origin | finding/limit |
|---|---|---|---|
| tiki reads markdown + YAML frontmatter (`id`, `title`, `status`, `priority`, open extra keys), views via `ruki` select, read-only git, agent skills for Claude Code | source-verified | github.com/boolean-maybe/tiki README, fetched 2026-11-04 | README only; ruki expressiveness not tested |
| SDD task files are already close to tiki items | source-verified | esp-deck docs/features/semi-autonomous-deck/tasks/t1-power-arbiter.md:1-13 | have `id`/`title`/`status`, but `id: T1` ≠ tiki's 6-char uppercase id |
| tiki accepts or rejects non-6-char ids like `T1` | source-verified | tiki docs/tiki-format.md, fetched 2026-11-04 | id must match `^[A-Z0-9]{6}$`; malformed ids are reported in diagnostics, so SDD tasks need a generated view (e.g. `PR2379`-style ids) |
| gate data refresh is slow | source-verified | `PR_GATES_JSON=1 pipeline-stamp.sh gates`, run 2026-11-04 | took >5 min (moved to background); the view is only as fresh as the last refresh |

## 7. Recommendation

- Owner-accepted 2026-11-04: start as an **observer** (read-only: derive state from artifacts, git and PR gates; show it). Dispatcher and own pipeline are later options, not now.
- Owner-stated first target: render `/board-fleet` and `/fleet` better.
- Proposal (not yet accepted): tiki is a generated **view**, not a store — cards are rebuilt from `PR_GATES_JSON=1 pipeline-stamp.sh gates` each run, so they cannot drift. Prototype runs on live data: 18 cards, ruki `select … where "MAIN" in tags` works (source-verified 2026-11-04, scratchpad prototype).

## 8. Open questions

_Pending._
