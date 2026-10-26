# pal — Raycast-style palette in hs.webview

Two halves, one contract. `pal/index.html` (UI, owner: 🎨ui) renders and handles
keys. `modules/pal.lua` (backend, owner: 🔧lua) owns the window, data, sqlite and
every side effect. Neither edits the other's file. Changes to this contract go
through the lead.

Mike's picks (from the decision board): Raycast two-pane + folder rail on the
left, inline descriptions + hotkey badge on the right, footer hints, ⌘K action
panel, app tile grid, header = single line OR chips (user setting), many
themes (user setting), ONE hotkey (⌥⇧Space), Alfred keywords, LaunchBar-style
learned abbreviations, zshrc aliases/functions as commands, sqlite frecency.

## Window

Lua: `hs.webview` borderless, transparent, ~880×540, centered on the focused
window's screen, `allowTextEntry(true)`, level modalPanel, loads
`file://~/.hammerspoon/pal/index.html` ONCE and keeps it (hide/show, never
reload per open). Hides on focus loss.

## Messages JS → Lua

`window.webkit.messageHandlers.pal.postMessage({type, ...})`

| type | fields | Lua does |
|---|---|---|
| `ready` | — | sends `init` |
| `folder` | `id` | sends `folder` (items + status for that folder) |
| `preview` | `id` | sends `preview` (async ok) |
| `run` | `id`, `q` (query typed), `action` (default `"run"`) | hides window, records usage (+abbrev q→id), performs action |
| `query` | `q` | for Lua-side keywords (see below) sends `provide` |
| `set` | `k`, `v` | persists a setting (`theme`, `header`), echoes `settings` |
| `hide` | — | hides window |
| `copy` | `text` | pasteboard, hide |
| `open` | `url` | opens URL, hide |

## Messages Lua → JS

`PAL.recv(payload)` via `evaluateJavaScript`. `payload.type`:

- `init`: `{folders:[Folder], items:[Item], usage:{id:{n,last}}, abbrev:{q:{id:n}}, settings:{theme, header}, keywords:[Keyword], themes?:[]}` — `items` is the Home set.
- `folder`: `{id, items:[Item], status:Status}`
- `preview`: `{id, title?, body, mono?:bool}` — body is plain text (UI escapes it).
- `provide`: `{q, items:[Item]}` — results for a Lua keyword query; UI shows them only if `q` still equals the box.
- `settings`: `{theme, header}`
- `open`: `{}` — window was just shown; UI focuses the input, keeps last folder, selects row 1.

## Shapes

```
Folder  = {id, name, icon, view?: "list"|"tiles"}
Item    = {id, t, s?, ic, f?, k, hk?, kw?, acts?}
  t   title            s  description shown dimmed inline
  ic  emoji OR "data:image/png;base64,…" (app icons)
  f   folder id it belongs to (Home shows all)
  k   kind: cmd|app|zsh|just|rem|note|task|pr|proj|clip|snip|proc|file|theme|folder|sys
  hk  existing hotkey label, e.g. "⌥⇧←" (right-side badge)
  kw  exact keyword/alias (typing it ranks this first)
  acts extra ⌘K actions: [{id, t, hk?}]; every item also gets run / copy / favourite
Status  = {line:"📁 dotfiles  🌿 master → origin  ✏️ 35  🕐 6d ago  ·  🔔6", chips:["📁 dotfiles","🌿 master",…]}
Keyword = {kw, t, url?}   url with %s → JS opens it; no url → Lua keyword
```

## Keywords

JS-side (no Lua round trip): `= expr` and bare math → calculator (Enter copies);
web keywords from `init.keywords` with `url` (g, gh, yt, w, tr, lin…).
Lua-side (`query` → `provide`): `$ cmd` shell (preview = output), `? text` ask
Claude, `f name` files, `:8000` port owners, `p name` processes, `rem text` add
reminder, `td text` Todoist add.

## Ranking (JS)

score = fuzzy(subsequence, word-start bonus) + 1000·(q == kw) + 400·abbrev[q][id]
+ 8·log2(1+usage.n) decayed by days since last. Empty query: favourites, then
frecency.

## Keys (JS)

↑↓ move · ↵ run · ⌘↵ secondary (first of acts) · Esc closes panel → clears
query → hides · ⇥/⇧⇥ next/prev folder · ⌘1–9 folder · ⌘K actions ·
⌘T next theme · ⌘H header line/chips. Mouse: click row runs, click rail switches.

## Additions (lead, after UI v1)

- Home folder id is `"home"`, first in `init.folders`.
- `init.favs` (and `settings.favs`) = array of favourite item ids. `run{action:"fav"}` does NOT hide; Lua toggles and echoes `settings` with new `favs`.
- `run{action:"copy"}` copies the item's command/title, then hides.
- Themes: night, paper, terminal, catppuccin-mocha, tokyo-night, nord, gruvbox-dark, dracula, rose-pine, solarized-light, kanagawa, everforest.
