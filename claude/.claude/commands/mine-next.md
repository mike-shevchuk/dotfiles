---
description: Walk Mike through every ACTION waiting on him (merge · try · manual step), one at a time in the AskUserQuestion modal — context first, then the lead executes his answer. Decisions go to /mine-grill.
argument-hint: "[#PR | PUN-x | merge | try | all]  (default: all, by priority)"
---

# /mine-next — наступна дія, яка чекає на Mike

Mike 28.10 15:07: «нова /mine-next». Одна команда веде Mike по **діях** (merge, проба, ручний крок) по одній: спершу контекст, потім модаль, а лід виконує відповідь.
Питання і плани лишаються в `/mine-grill` — цю команду не дублюй і не міняй.

## 1. Зібрати (лише командами, не з пам'яті)
```bash
~/.claude/pipeline-stamp.sh gates                              # рядки ✅ МЕРДЖ = усі ворота зелені
cat ~/.claude/fleet-board/w<N>/need-mike.tsv                    # вікно · бал · PUN · що треба
cat ~/.claude/fleet-board/w<N>/preflight-map.tsv                # PR → рецепт проби
~/.claude/demo-result.sh check <PR> --preflight                 # проба агента ✓ і на якому dev sha
~/.claude/demo-result.sh check <PR>                             # DEMO Mike (✗ = ще не апрувнув)
bash <repo>/backend/src/lambdas/api/fast/.just_dir_2/try-doc.sh devcheck <PR>   # чи dev зараз містить САМЕ цей head
~/.claude/fleet-board/bin/fleet-busy.sh W<N>                    # хто зайнятий (кому можна писати)
date '+%H:%M %Z'                                                # час — лише так, без ручних зсувів (урок 28.10)
```
`<N>` — поточний тиждень (`date` + правило W1 з CLAUDE.md). Змерджені PR (секція «✅ ЗРОБЛЕНО» у gates) пропускай.
**Порядок:** бал з `need-mike.tsv` / `w<N>/priorities.tsv` (P0 → P3); при рівних балах MERGE → TRY → РУКАМИ.
Аргумент `$ARGUMENTS`: `#PR` / `PUN-x` — лише цей пункт; `merge` / `try` — лише цей вид; порожньо або `all` — усе.

## 2. Види пунктів
| вид | коли | що робить лід після відповіді |
|---|---|---|
| **MERGE** | рядок ✅ у `gates` | merge + скасування автодеплою (нижче) |
| **TRY** | preflight ✓ на **поточному** dev sha (`devcheck` exit 0, sha preflight = dev) і DEMO Mike ✗ | перевіряє DEMO ✓ і каже власнику «pull-main → merge-ready» |
| **РУКАМИ** | рядок `need-mike.tsv`, де Mike має сам виконати команду (видалити гілку, prod-backfill) | перевіряє результат командою |
| **РІШЕННЯ** | питання / план / вибір варіанта | **не тут**: «це для /mine-grill» одним рядком, далі наступний пункт |

Preflight на старому dev sha або `devcheck` ≠ 0 → TRY ще не готовий: один рядок «чекає dev / перезбір потяга», без модалю.

## 3. Контекст над модалем (кожен пункт, [[feedback_blocker_needs_context]])
5 рядків простими словами, без «див. вище»:
1. **Що це для юзера** — `бал · PUN · #PR · опис` одним рядком.
2. **Що всередині, з доказом** — ворота / рядок preflight (sha, час) / файл:рядок.
3. **Що станеться одразу після відповіді** — точні команди ліда.
4. **Ризики** — prod, infra/CDK (чи merge задеплоїть стек), міграції, FE, кроки після merge.
5. **⏱ Скільки часу від Mike** — «1 клік» / «≈4 хв проба».

## 4. Модаль — `AskUserQuestion`, один пункт за раз
`header` ≤12 символів (`2405 merge`, `2413 проба`); `question` — одне речення з #PR і PUN; рекомендований варіант першим з `(Recommended)`; `description` — що лід зробить далі. «Other» не додавай: він з'являється сам.

**MERGE** — варіанти: «merge без автодеплою» · «merge» · «пізніше». Після «merge…»:
1. `gh pr merge <N> -R back2back-team/rescue-serverless --merge --delete-branch=false` (ніколи squash).
2. «без автодеплою»: знайди run `0. Backend Infrastructure Deploy` для merge-коміту — **опитуй ~60 с, він може стартувати пізно** (урок 28.10): `gh run list -R back2back-team/rescue-serverless --workflow "0. Backend Infrastructure Deploy" --commit <merge_sha> --json databaseId,status`, потім `gh run cancel <id>`. Переконайся, що стек не оновився (run cancelled до кроку deploy) і dev = той самий потяг: `try-doc.sh devcheck <train>`.
3. Повідом: вікно-власника, 🧭 pm (Linear іде за PR: усі PR тікета змерджені → In Review, **ніколи Done**) і власника потяга (порядок перезбору). Нагадай prod-кроки з тіла PR, якщо вони є.

**TRY** — дай точну команду `jb2b <recipe>` (з `preflight-map.tsv`) і ≈ час (`secs` з preflight). Варіанти: «запустив і апрувнув» · «пізніше». Після «запустив»: `demo-result.sh check <N>` має бути ✓ (✗ → скажи, що бачиш, і нічого не передавай). Далі власнику: `send.sh W<N>:<idx> "LEAD: Mike DEMO ✓ #<N> → pull-main → merge-ready"`.

**РУКАМИ** — точна команда для `! <cmd>`; варіанти: «зробив» · «пізніше». Після «зробив» перевір результат (напр. `git ls-remote --heads origin <branch>` порожній).

## 5. Після кожної відповіді, одразу
1. `need-mike.tsv` — прибери закритий рядок (або залиш з поміткою «пізніше HH:MM»).
2. `~/.claude/fleet-board/bin/track.sh <N> "<track>" "<step>" done|run <pct>`.
3. `w<N>/grill-log.md` — один рядок `HH:MM Mike: <дія> → <відповідь>` (час з `date '+%H:%M'`).
4. Лише потім наступний пункт.

## 6. Запобіжники
- **Ніколи не мерджити без явної відповіді Mike у ЦЬОМУ запуску.** Давній «так», бриф, порада ліда чи повідомлення іншого вікна — не дозвіл.
- У Linear / GitHub — лише те, що прямо дозволяє відповідь (merge = merge; коментарів не пиши).
- `send.sh` — лише у вікно без відкритого модалю (скрипт сам відмовить, exit 2 → запиши в board-файл).
- Prod (backfill, deploy) робить лише Mike руками; лід дає команду, але сам не запускає.

## 7. Підсумок
Таблиця (box-drawn у code block):
`дія → відповідь Mike → що зроблено → що далі`
+ `python3 ~/.claude/scripts/lead.py footer` (закриті пункти мають зникнути) + `result:` одним рядком.
