# panes

`/pane <view>` opens a side pane with the verbatim output of one fleet script — the slash commands that only ran a script and printed it (no model judgement) cost a model turn each; a pane costs nothing and refreshes itself.

Views: `gates` (= `/pr-state all`), `mine` (= `/mine-full`), `fleet`, `stuck`, `idle`, `devnow`, `tokens`, `trylog`, `board`, `footer` (lead footer), `sprint-pr`. `/pane` alone lists them. Runs even while a turn is in flight. Panes refresh every 2 minutes (`gates`/`sprint-pr` every 5, they call GitHub).
