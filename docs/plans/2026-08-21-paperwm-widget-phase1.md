# PaperWM Widget Phase 1 — Modularize + De-lag — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 1234-line `paperwmui.lua` into five focused modules and remove the three named lag sources, with no user-visible behavior change.

**Architecture:** Extract a zero-dependency pure-math module (`paperwmgeom`), a single PaperWM adapter (`paperwmmodel`, the only file touching `pwm.*`/`paperwmfit`), a canvas renderer (`paperwmrender`) that reuses one persistent canvas and replaces elements in place, an interaction module (`paperwminteract`) that defers window writes to drag-release, and a thin coordinator (`paperwmui`) that keeps the public API `init.lua` already calls.

**Tech Stack:** Lua 5.5 (Hammerspoon runtime), `hs.canvas`, `hs.window.filter`, PaperWM.spoon. Pure math unit-tested with standalone `lua`; effectful code smoke-tested via `hs -c "hs.reload()"` + `hs.console`.

**Spec:** `docs/specs/2026-08-21-paperwm-widget-redesign.md`

## Global Constraints

- **No tests committed to the branch.** Test files live under `hammerspoon/.hammerspoon/modules/spec/` which this plan adds to `.gitignore`. Every commit adds source files only — never a file under `modules/spec/`.
- **No behavior change in Phase 1.** After every task, the widget must look and act exactly as before; only structure and latency change.
- **`paperwmmodel.lua` is the sole owner of PaperWM internals.** `geom`, `render`, `interact`, `ui` must not reference `paperwm.pwm`, `pwm.state.*`, `pwm.floating.*`, `pwm.windows.*`, or `paperwmfit` except through `model`'s API. (`render` may read the exported `paperwmfit.MIN` constant via `model.minRatio()`.)
- **`paperwmui.lua` public API is frozen:** `start()`, `show()`, `toggleFullWidth()`, `toggleFullscreen()` must keep the same names and semantics — `init.lua` binds them and must not be edited.
- **`paperwmgeom.lua` must load under plain `lua`** — zero `require`, zero `hs.*` calls at load time and in every exported function. All drawing constants it needs are passed in or defined as plain numbers/tables in the module.
- **Reload gate:** each task ends with `hs -c "hs.reload()"` returning no error in `hs.console`, and the widget still drawing.
- Commit messages in English. No `Co-Authored-By` line. Scoped `git add <paths>` only — never `git add -A`.
- Work happens in the worktree at `~/dotfiles/.claude/worktrees/hamerspoon`, branch `feat/hammerspoon-trackpad-controls`. Module files live in `hammerspoon/.hammerspoon/modules/`.

---

## File Structure (Phase 1 end state)

- `modules/paperwmgeom.lua` — **new.** Pure math: `layout`, `columnAt`, `chipsWidth`, `clampOffset`, `stripHash`, `redrawTier`. Zero deps. Unit-tested.
- `modules/paperwmmodel.lua` — **new.** PaperWM adapter. Reads (`strip`, cache, `invalidate`, `minRatio`, `floorRatio`) + writes (`setWidth`, `moveColumn`, `toggleFloat`, `scrollTo`, `scrollStep`, `fullWidth`, `toggleFullWidth`, `toggleFullscreen`, `stack`, `unstack`). Only file importing `paperwm`/`paperwmfit`.
- `modules/paperwmrender.lua` — **new.** Persistent canvas ownership, element build, `replaceElements`, two-tier redraw, caret canvas.
- `modules/paperwminteract.lua` — **new.** `mouseCallback`, drag state, hit-testing via `geom`, defer-write-on-release.
- `modules/paperwmui.lua` — **rewritten thin.** Menubar, shared-filter subscription, pin/flash, wiring. Public API frozen.
- `modules/spec/*.lua` — **new, gitignored.** Standalone test files.
- `.gitignore` — add `hammerspoon/.hammerspoon/modules/spec/`.

The extraction preserves the exact logic currently in `paperwmui.lua`; source line ranges below refer to the current file (read it alongside this plan).

---

## Task 1: Pure geometry module + unit tests

Extract the functions that are already pure (or trivially made pure) into a standalone, testable module. This is the foundation the renderer and interaction modules build on.

**Files:**
- Create: `hammerspoon/.hammerspoon/modules/paperwmgeom.lua`
- Create (gitignored): `hammerspoon/.hammerspoon/modules/spec/geom_spec.lua`
- Modify: `.gitignore` (add the spec dir)

**Interfaces:**
- Produces:
  - `geom.DIMS` — table of drawing constants: `{ STRIP_W=560, BOX_H=42, GAP=6, PAD=22, MIN_BOX=46, FLOAT_W=74, SEP=18, CHIP_H=22, CHIP_G=5, SLIDER_H=24, SLIDER_MAXW=420, WIDTH_CHIP=44, ACT_CHIP=60 }`.
  - `geom.layout(s, dims)` → `boxes, floats, totalW, viewport` where
    `boxes[i] = { col, entry, x, w }`,
    `floats[i] = { x, w, win }`,
    `viewport = { x, w, offset, scale }`.
    `s` is a strip snapshot with fields `columns` (each `{ vx, px, wins, ratio }`), `floating`, `canvas={x,w}`, `left`, `stripW`. Pure; `dims` defaults to `geom.DIMS`.
  - `geom.columnAt(x, boxes)` → column number nearest `x`, or `nil` if `boxes` empty.
  - `geom.chipsWidth(chips, dims)` → total px width of a chip row (`chips[i]` is `{ w }` or `{ gap=true }`).
  - `geom.clampOffset(offset, stripW, canvasW)` → offset clamped to `[0, max(0, stripW-canvasW)]`.
  - `geom.stripHash(s)` → string encoding `{ col, column order by first-window id, per-column rounded width px, sorted floating ids }`. Two snapshots that should trigger a full relayout must hash differently; a pure focus move (only `s.col` changed) also changes the hash (so the coordinator can still detect it) — see `redrawTier`.
  - `geom.redrawTier(prevHash, newHash)` → `"none"` if equal, else `"full"`. (Phase 1 keeps this binary; Task 5 adds the `"cheap"` tier and its own richer inputs — do not pre-build it here.)
- Consumes: nothing.

- [ ] **Step 1: Write the failing tests**

Create `hammerspoon/.hammerspoon/modules/spec/geom_spec.lua`:

```lua
-- standalone: run with `lua geom_spec.lua` from modules/
package.path = "./?.lua;" .. package.path
local geom = require("paperwmgeom")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function approx(a, b) return math.abs(a - b) < 0.5 end

-- layout: two columns, strip == screen width, no scaling
local s = {
  columns = {
    { vx = 0,   px = 300, wins = {}, ratio = 0.5 },
    { vx = 300, px = 300, wins = {}, ratio = 0.5 },
  },
  floating = {},
  canvas = { x = 0, w = 600 },
  left = 0,
  stripW = 600,
}
local boxes, floats, totalW, vp = geom.layout(s)
check("layout: two boxes", #boxes == 2)
check("layout: box1 x == PAD", approx(boxes[1].x, geom.DIMS.PAD))
check("layout: scale maps stripW to STRIP_W", approx(vp.scale, geom.DIMS.STRIP_W / 600))
check("layout: box2 x scaled", approx(boxes[2].x, geom.DIMS.PAD + 300 * (geom.DIMS.STRIP_W / 600)))
check("layout: no floats", #floats == 0)
check("layout: viewport width == canvas scaled", approx(vp.w, 600 * (geom.DIMS.STRIP_W / 600)))

-- columnAt: pointer inside box 2 returns 2; far left returns 1; far right returns last
check("columnAt: inside box2", geom.columnAt(boxes[2].x + 1, boxes) == 2)
check("columnAt: far left clamps to first", geom.columnAt(-9999, boxes) == 1)
check("columnAt: far right clamps to last", geom.columnAt(99999, boxes) == 2)
check("columnAt: empty -> nil", geom.columnAt(10, {}) == nil)

-- chipsWidth: two 44px chips + one gap
local chips = { { w = 44 }, { gap = true }, { w = 44 } }
check("chipsWidth: positive", geom.chipsWidth(chips) > 88)

-- clampOffset
check("clampOffset: below 0", geom.clampOffset(-5, 1000, 600) == 0)
check("clampOffset: above max", geom.clampOffset(9999, 1000, 600) == 400)
check("clampOffset: within", geom.clampOffset(100, 1000, 600) == 100)
check("clampOffset: strip <= canvas -> 0", geom.clampOffset(50, 500, 600) == 0)

-- stripHash / redrawTier
local h1 = geom.stripHash(s)
local s2 = { columns = s.columns, floating = {}, canvas = s.canvas, left = 0, stripW = 600, col = 2 }
local h2 = geom.stripHash(s2)
check("redrawTier: identical -> none", geom.redrawTier(h1, h1) == "none")
check("redrawTier: changed -> full", geom.redrawTier(h1, h2) == "full")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/dotfiles/.claude/worktrees/hamerspoon/hammerspoon/.hammerspoon/modules && lua spec/geom_spec.lua`
Expected: FAIL — `module 'paperwmgeom' not found`.

- [ ] **Step 3: Write `paperwmgeom.lua`**

Create `hammerspoon/.hammerspoon/modules/paperwmgeom.lua`. Move the body of `layout` (current `paperwmui.lua:603-636`) and `chipsWidth` (`591-598`) verbatim, parameterizing the drawing constants through `dims`. Adapt `columnAt` (`313-319`) to take `boxes` as a parameter instead of `M.boxes`. Write `clampOffset`, `stripHash`, `redrawTier` fresh:

```lua
-- Pure geometry + redraw-tier math for the PaperWM widget.
-- Zero dependencies: loads under plain `lua`, calls no hs.* — so every function
-- here is unit-testable without a running Hammerspoon.
local M = {}

M.DIMS = {
  STRIP_W = 560, BOX_H = 42, GAP = 6, PAD = 22,
  MIN_BOX = 46, FLOAT_W = 74, SEP = 18,
  CHIP_H = 22, CHIP_G = 5, SLIDER_H = 24, SLIDER_MAXW = 420,
  WIDTH_CHIP = 44, ACT_CHIP = 60,
}

-- The map covers the whole strip; every column keeps its true proportion and a
-- frame marks the visible slice. (moved from paperwmui.layout)
function M.layout(s, dims)
  dims = dims or M.DIMS
  local PAD, STRIP_W, GAP, FLOAT_W, SEP = dims.PAD, dims.STRIP_W, dims.GAP, dims.FLOAT_W, dims.SEP
  local mapW = STRIP_W
  local scale = s.stripW > 0 and (mapW / s.stripW) or 1

  local boxes = {}
  for col, e in ipairs(s.columns) do
    boxes[#boxes + 1] = {
      col = col, entry = e,
      x = PAD + (e.vx - s.left) * scale,
      w = math.max(8, e.px * scale),
    }
  end

  local viewport = {
    x = PAD + (s.canvas.x - s.left) * scale,
    w = s.canvas.w * scale,
    offset = s.canvas.x - s.left,
    scale = scale,
  }

  local x = PAD + mapW
  local floats = {}
  if #s.floating > 0 then
    x = x + SEP
    for _, w in ipairs(s.floating) do
      floats[#floats + 1] = { x = x, w = FLOAT_W, win = w }
      x = x + FLOAT_W + GAP
    end
    x = x - GAP
  end

  return boxes, floats, x + PAD, viewport
end

-- which column the pointer is over (moved from paperwmui.columnAt, boxes param)
function M.columnAt(x, boxes)
  if not boxes or #boxes == 0 then return nil end
  for _, b in ipairs(boxes) do
    if x >= b.x and x <= b.x + b.w then return b.col end
  end
  return x < boxes[1].x and boxes[1].col or boxes[#boxes].col
end

function M.chipsWidth(chips, dims)
  dims = dims or M.DIMS
  local total = 0
  for i, c in ipairs(chips) do
    total = total + (c.gap and 12 or c.w)
    if i < #chips then total = total + dims.CHIP_G end
  end
  return total
end

function M.clampOffset(offset, stripW, canvasW)
  local maxOffset = math.max(0, stripW - canvasW)
  return math.max(0, math.min(offset, maxOffset))
end

-- Stable string fingerprint of what the map draws. Order is by each column's
-- first-window id so a reorder changes the hash; widths are rounded to the px so
-- sub-pixel jitter does not force a redraw. Floating ids are sorted.
function M.stripHash(s)
  local parts = { "c=" .. tostring(s.col) }
  for _, e in ipairs(s.columns) do
    local first = e.wins and e.wins[1]
    local id = first and (first.id and (type(first.id) == "function" and first:id() or first.id)) or "?"
    parts[#parts + 1] = tostring(id) .. ":" .. tostring(math.floor((e.px or 0) + 0.5))
  end
  local fids = {}
  for _, w in ipairs(s.floating or {}) do
    fids[#fids + 1] = tostring(w.id and (type(w.id) == "function" and w:id() or w.id) or "?")
  end
  table.sort(fids)
  parts[#parts + 1] = "f=" .. table.concat(fids, ",")
  return table.concat(parts, "|")
end

function M.redrawTier(prevHash, newHash)
  if prevHash == newHash then return "none" end
  return "full"
end

return M
```

Note the `stripHash` id shim handles both real HS windows (`win:id()`) and plain test tables (`{id=…}`); the test passes `wins = {}` so ids read `"?"` — that is fine, the test only checks hash inequality driven by `col`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/dotfiles/.claude/worktrees/hamerspoon/hammerspoon/.hammerspoon/modules && lua spec/geom_spec.lua`
Expected: `13 passed, 0 failed`, exit 0.

- [ ] **Step 5: Point `paperwmui.lua` at `geom` (keep behavior identical)**

In `paperwmui.lua`: add `local geom = require("modules.paperwmgeom")` near the other requires. Delete the local `layout` (603-636), `chipsWidth` (591-598), and `columnAt` (313-319). Replace their call sites:
- `layout(s)` → `geom.layout(s, geom.DIMS)` — but `layout` uses the module constants `PAD, STRIP_W, …`; keep those top-level constants in `paperwmui` for the rest of `draw()` (they are still referenced there in Phase 1), and rely on `geom.DIMS` having the same values.
- `columnAt(x)` → `geom.columnAt(x, M.boxes)`.
- `chipsWidth(chips)` → `geom.chipsWidth(chips, geom.DIMS)`.

Confirm the numeric constants at the top of `paperwmui.lua` still equal `geom.DIMS` (they do — copied from there). No behavior change.

- [ ] **Step 6: Reload gate**

Run: `hs -c "hs.reload()"` then `hs -c "hs.console.getConsole()" | tail -20`
Expected: no Lua error; press `⌃⌥⌘U` (or run `hs -c "require('modules.paperwmui').show()"`) — the strip map still draws, boxes and chips positioned as before.

- [ ] **Step 7: Commit (source only)**

```bash
cd ~/dotfiles/.claude/worktrees/hamerspoon
git add hammerspoon/.hammerspoon/modules/paperwmgeom.lua \
        hammerspoon/.hammerspoon/modules/paperwmui.lua \
        .gitignore
git commit -m "refactor(paperwm): extract pure geometry into paperwmgeom"
```
(Add `hammerspoon/.hammerspoon/modules/spec/` to `.gitignore` in this step before committing; verify `git status` shows no `modules/spec/` file staged.)

---

## Task 2: PaperWM adapter module (`paperwmmodel`)

Move all state reads and window mutations behind one adapter — the only file that knows PaperWM's internals.

**Files:**
- Create: `hammerspoon/.hammerspoon/modules/paperwmmodel.lua`
- Modify: `hammerspoon/.hammerspoon/modules/paperwmui.lua`

**Interfaces:**
- Consumes: `paperwm`, `paperwmfit`, `focusborder` (for menu toggles later — not here).
- Produces (`model.*`):
  - `model.strip()` → snapshot table (today's `computeStrip` result) or `nil`. Cached ~0.25s.
  - `model.invalidate()` — clear the strip cache.
  - `model.shortName(win)` → ≤10-char label.
  - `model.minRatio()` → `paperwmfit.MIN`.
  - `model.floorRatio(win)` → app's minimum width as a screen share.
  - `model.setWidth(win, ratio)`, `model.fullWidth(win)`.
  - `model.moveColumn(space, from, to)`.
  - `model.toggleFloat(win)`.
  - `model.stack(win)` / `model.unstack(win)` — focus-then-slurp/barf (today's `withFocus` wrapping).
  - `model.scrollTo(offset)` (public wrapper) and `model.scrollToStrip(s, offset)` (the internal variant taking a snapshot), `model.scrollStep(dir)`.
  - `model.toggleFullWidth()`, `model.toggleFullscreen()` — moved verbatim; `paperwmui` re-exports them.
  - `model.onChange(fn)` — register the coordinator's coalesced redraw callback; `model` calls it after every mutation instead of the old module-local `afterChange`.

- [ ] **Step 1: Create `paperwmmodel.lua` by moving read/write code**

Move verbatim from `paperwmui.lua` into `paperwmmodel.lua`, renaming to the `model.*` API above:
- `shortName` (50-55) → `model.shortName`.
- `stripCache`/`invalidate`/`computeStrip`/`strip` (57-149) → `model.strip` + private cache + `model.invalidate`.
- `setWidth` (165-181), `prevRatio`/`fullWidth` (186-200), `floorRatio` (205-212) → `model.setWidth`, `model.fullWidth`, `model.floorRatio`.
- `scrollTo` local (250-288), `M.scrollTo` (292-296), `scrollStep`/`STEP` (237-245) → `model.scrollToStrip`, `model.scrollTo`, `model.scrollStep`.
- `moveColumnTo` (301-310) → `model.moveColumn`.
- `withFocus` (364-375) → private; `toggleFloat` (379-384) → `model.toggleFloat`; add `model.stack(win)=withFocus(win, pwm.windows.slurpWindow)` and `model.unstack(win)=withFocus(win, pwm.windows.barfWindow)`.
- `M.toggleFullWidth` (392-423), `M.beforeFull`, `M.zoomed`, `M.toggleFullscreen` (431-462) → `model.toggleFullWidth`, `model.toggleFullscreen`.
- Add `model.minRatio() return paperwmfit.MIN end`.

Replace the old `afterChange` (154-163): `model` calls `M.changeCb and M.changeCb()` at the end of each mutation, and exposes `model.onChange(fn) M.changeCb = fn end`. `model` still calls `paperwmfit.setDesired/refit` inside `setWidth` exactly as today.

- [ ] **Step 2: Rewire `paperwmui.lua` to use `model`**

In `paperwmui.lua`: `local model = require("modules.paperwmmodel")`. Replace every call to the moved functions with `model.*`. Re-export the frozen API:

```lua
M.toggleFullWidth  = model.toggleFullWidth
M.toggleFullscreen = model.toggleFullscreen
```

Register the coalesced redraw (this replaces the old `afterChange` timer that lived in `paperwmui`):

```lua
local refreshTimer
model.onChange(function()
  model.invalidate()
  if refreshTimer then refreshTimer:stop() end
  refreshTimer = hs.timer.doAfter(0.25, function()
    M.update()
    if M.pinned then M.draw() end
  end)
end)
```

`draw()` and the mouse callback still live in `paperwmui` for now; they call `model.strip()`, `model.setWidth`, etc.

- [ ] **Step 3: Reload gate + behavior smoke**

Run: `hs -c "hs.reload()"`; check `hs.console` for errors.
Smoke: with the map pinned (`⌃⌥⌘U`), verify every action still works — click a box to focus, ◀▶ reorder, width chips resize, stack/unstack, float/unfloat, width slider, view slider, `⌃⌥⌘F` full width, `⌃⌥⌘↩` full screen. All must behave exactly as before.
Console assertion: `hs -c "print(type(require('modules.paperwmmodel').strip()))"` → `table` (with windows open).

- [ ] **Step 4: Commit**

```bash
git add hammerspoon/.hammerspoon/modules/paperwmmodel.lua \
        hammerspoon/.hammerspoon/modules/paperwmui.lua
git commit -m "refactor(paperwm): extract PaperWM adapter into paperwmmodel"
```

---

## Task 3: Interaction module (`paperwminteract`)

Move the mouse callback, drag state, and caret into their own module. Behavior stays identical (defer-write comes in Task 6).

**Files:**
- Create: `hammerspoon/.hammerspoon/modules/paperwminteract.lua`
- Modify: `hammerspoon/.hammerspoon/modules/paperwmui.lua`

**Interfaces:**
- Consumes: `model`, `geom`. Reads the current draw geometry via an injected accessor (see below) so it never rebuilds the map.
- Produces:
  - `interact.attach(canvas, ctx)` — installs the `mouseCallback` on the render canvas. `ctx` is `{ boxes(), viewport(), sliders(), canvasFrame(), pinned(), afterUpdate(fn) }` — thin getters the coordinator supplies so `interact` reads live geometry without owning it.
  - `interact.dropAt(from, x)`, `interact.applySlider(x)`, `interact.applyScroll(x)` — kept public for console verification.
  - `interact.isDragging()` → bool (render checks this to skip full rebuilds).

- [ ] **Step 1: Move the callback + drag helpers**

Move into `paperwminteract.lua`, verbatim except routing through `model`/`geom`/`ctx`:
- caret canvas: `caretShow`/`caretHide` (323-351) — the caret is interaction feedback, it belongs here.
- `applySlider` (215-224), `applyScroll` (227-232), `dropAt` (355-360).
- the whole `M.canvas:mouseCallback(function(...) … end)` body (979-1155) → `interact.attach`'s installed handler.
- drag state fields (`M.dragging`, `M.drag`, `M.vpDrag`, `M.dragGuard`, `M.lastDrag`, `M.slider`, `M.scrollSlider`, `M.viewport`, `M.boxes`, `M.canvasFrame`) → `interact` local state, exposed via `interact.isDragging()` and set from `ctx` getters where they are draw outputs (`boxes`, `viewport`, `sliders`, `canvasFrame`).

`M.dragging` reads in `draw()` (639) become `interact.isDragging()`.

- [ ] **Step 2: Wire from `paperwmui.draw()`**

At the end of `draw()`, after building the canvas, instead of installing the callback inline, publish the geometry and attach once:

```lua
M._geom = { boxes = boxes, viewport = viewport, canvasFrame = M.canvasFrame,
            slider = M.slider, scrollSlider = M.scrollSlider }
interact.attach(M.canvas, {
  boxes        = function() return M._geom.boxes end,
  viewport     = function() return M._geom.viewport end,
  sliders      = function() return M._geom.slider, M._geom.scrollSlider end,
  canvasFrame  = function() return M._geom.canvasFrame end,
  pinned       = function() return M.pinned end,
  afterUpdate  = function() M.update() end,
})
```

(In Task 4 `attach` is called once at canvas creation, not per draw; for now calling it each draw is acceptable since the canvas is still recreated each draw.)

- [ ] **Step 3: Reload gate + full interaction smoke**

Run: `hs -c "hs.reload()"`; check console.
Smoke every gesture again (focus click, drag-reorder with caret, vertical-drag stack/unstack, width slider drag, view slider drag, viewport-frame drag, ◀▶ steps, chips, close ✕). Identical behavior.
Console: `hs -c "print(require('modules.paperwminteract').isDragging())"` → `false`.

- [ ] **Step 4: Commit**

```bash
git add hammerspoon/.hammerspoon/modules/paperwminteract.lua \
        hammerspoon/.hammerspoon/modules/paperwmui.lua
git commit -m "refactor(paperwm): extract mouse/drag interaction into paperwminteract"
```

---

## Task 4: Renderer module + persistent canvas (perf fix #1)

Move drawing into `paperwmrender` and stop tearing the canvas down every frame.

**Files:**
- Create: `hammerspoon/.hammerspoon/modules/paperwmrender.lua`
- Modify: `hammerspoon/.hammerspoon/modules/paperwmui.lua`, `hammerspoon/.hammerspoon/modules/paperwminteract.lua`

**Interfaces:**
- Consumes: `geom`, `model`.
- Produces:
  - `render.draw(s, opts)` → `geomOut` where `geomOut = { boxes, floats, viewport, canvasFrame, slider, scrollSlider, canvas }`. `opts = { pinned, screen }`. Builds the element list and, if the canvas already exists at the same frame, calls `canvas:replaceElements(els)`; otherwise creates the canvas once and `appendElements`. Returns the geometry the coordinator publishes to `interact`.
  - `render.canvas()` → the persistent `hs.canvas` (so `interact.attach` binds once).
  - `render.hide()`.

- [ ] **Step 1: Move `draw` element-building into `render`**

Move the element-assembly half of `paperwmui.draw()` (640-977, i.e. everything that builds `els`) into `render.draw`. Keep the mouse-callback installation OUT (it lives in `interact`). Replace the teardown:

```lua
-- OLD (paperwmui.draw): M.canvas:delete(); M.canvas = hs.canvas.new(frame); … appendElements
-- NEW (render.draw):
local frameChanged = not M.canvas
  or M.frame.x ~= cf.x or M.frame.y ~= cf.y or M.frame.w ~= cf.w or M.frame.h ~= cf.h
if frameChanged then
  if M.canvas then M.canvas:frame(cf) else
    M.canvas = hs.canvas.new(cf)
    M.canvas:level(hs.canvas.windowLevels.overlay)
    M.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces |
      hs.canvas.windowBehaviors.stationary)
    M.canvas:clickActivating(false)
  end
  M.frame = cf
end
M.canvas:replaceElements(els)   -- reuse; never delete()+new() on a plain redraw
M.canvas:show()
```

- [ ] **Step 2: Coordinator calls render, attaches interact once**

`paperwmui.draw()` becomes:

```lua
function M.draw()
  if interact.isDragging() then return end
  local s = model.strip()
  if not s then render.hide(); return end
  local g = render.draw(s, { pinned = M.pinned, screen = M.screenForDraw() })
  M._geom = g
  interact.ensureAttached(render.canvas(), M.ctx)   -- attaches only on first call / new canvas
end
```

Add `interact.ensureAttached(canvas, ctx)` that installs the callback only when the canvas identity changes (compare against a stored ref). `M.screenForDraw()` = focused window's screen or `hs.screen.mainScreen()` (moved from 655-656).

- [ ] **Step 3: Smoke — the flicker test**

Run: `hs -c "hs.reload()"`.
Open 6+ windows on the strip, pin the map, then hop focus rapidly (`⌃⌥⌘←/→` held). Expected: the map updates without the visible flash/rebuild it had before; the boxes restyle smoothly; mouse tracking still works immediately after a focus hop (no dead first-click).

- [ ] **Step 4: Commit**

```bash
git add hammerspoon/.hammerspoon/modules/paperwmrender.lua \
        hammerspoon/.hammerspoon/modules/paperwmui.lua \
        hammerspoon/.hammerspoon/modules/paperwminteract.lua
git commit -m "perf(paperwm): reuse one canvas + replaceElements instead of teardown"
```

---

## Task 5: Two-tier redraw (perf fix #3)

Avoid a full relayout when only the focus highlight moved.

**Files:**
- Modify: `hammerspoon/.hammerspoon/modules/paperwmgeom.lua`, `hammerspoon/.hammerspoon/modules/paperwmrender.lua`
- Modify (gitignored): `hammerspoon/.hammerspoon/modules/spec/geom_spec.lua`

**Interfaces:**
- Produces (extends `geom`):
  - `geom.redrawTier(prev, new)` gains a `"cheap"` result: returns `"none"` if the full hash is equal, `"cheap"` if only the focused-column marker changed (same column set/order/widths/floating), else `"full"`. Inputs become structured: `geom.redrawTier(prev, new)` where each is `{ hash, col }` — `hash` excludes `col`, `col` is compared separately.
  - `render.draw` uses the tier: on `"cheap"` it mutates only the two affected column boxes' `fillColor`/`strokeColor`/text color via indexed element assignment (`canvas[i].fillColor = …`) instead of rebuilding `els`.

- [ ] **Step 1: Extend the failing tests**

Add to `geom_spec.lua`:

```lua
-- redrawTier: only focus changed -> cheap
local base = { hash = "H", col = 1 }
local moved = { hash = "H", col = 2 }
local relaid = { hash = "H2", col = 2 }
check("tier: identical -> none", geom.redrawTier(base, base) == "none")
check("tier: only col -> cheap", geom.redrawTier(base, moved) == "cheap")
check("tier: hash change -> full", geom.redrawTier(base, relaid) == "full")
```

- [ ] **Step 2: Run tests — verify the new ones fail**

Run: `cd …/modules && lua spec/geom_spec.lua`
Expected: FAIL on the three `tier:` checks (current `redrawTier` takes strings).

- [ ] **Step 3: Update `geom.stripHash`/`redrawTier`**

Change `stripHash` to exclude `col` (drop the leading `"c="` part), and rewrite `redrawTier`:

```lua
function M.redrawTier(prev, new)
  if not prev then return "full" end
  if prev.hash ~= new.hash then return "full" end
  if prev.col ~= new.col then return "cheap" end
  return "none"
end
```

Update the Task 1 tests that called `stripHash`/`redrawTier` with strings to pass `{hash=…, col=…}` (the earlier `redrawTier: changed -> full` check becomes a `full` via differing hash). Re-run: all pass.

- [ ] **Step 4: Apply the tier in `render.draw`**

`render` keeps `M.lastTier = { hash, col }` and the drawn element indices of each column's box + its label. On `render.draw`:

```lua
local tier = geom.redrawTier(M.lastTier, { hash = geom.stripHash(s), col = s.col })
if tier == "none" then return M.lastGeom end
if tier == "cheap" and M.canvas and M.boxIdx then
  -- restyle previously-focused and newly-focused boxes only
  M.recolorFocus(M.lastTier.col, s.col)
  M.lastTier = { hash = geom.stripHash(s), col = s.col }
  return M.lastGeom
end
-- full: build els, reuse canvas, replaceElements (Task 4 path)
```

`M.recolorFocus(oldCol, newCol)` sets `canvas[boxIdx[oldCol]].fillColor = FILL_OFF` etc. and the new col to `FILL_ON`/`ACCENT`, using the stored element indices. Guard bounds (a column may have closed → fall back to full).

- [ ] **Step 5: Reload gate + smoke**

Run: `hs -c "hs.reload()"`; `lua spec/geom_spec.lua` → all pass.
Smoke: focus-hop across columns — only the highlight moves, no full redraw; changing a width or count still does a full relayout correctly.

- [ ] **Step 6: Commit (source only)**

```bash
git add hammerspoon/.hammerspoon/modules/paperwmgeom.lua \
        hammerspoon/.hammerspoon/modules/paperwmrender.lua
git commit -m "perf(paperwm): cheap focus-only redraw via stripHash tiers"
```

---

## Task 6: Defer window writes to drag-release (perf fix #2)

Stop running the full mutation chain on every mouse-move during a drag.

**Files:**
- Modify: `hammerspoon/.hammerspoon/modules/paperwminteract.lua`, `hammerspoon/.hammerspoon/modules/paperwmrender.lua`

**Interfaces:**
- Produces:
  - `render.previewKnob(track, frac)` — moves only the slider knob / fill (or the viewport frame for the view track) in place, no window write. `track` ∈ `"width" | "view"`.
  - `interact` drag handlers call `render.previewKnob` on `mouseMove` and issue the single real `model.setWidth` / `model.scrollTo` on `mouseUp`. Optional live mode: a throttle constant `interact.LIVE_MS = 0` (0 = release-only; set >0 to allow throttled live writes).

- [ ] **Step 1: Add `render.previewKnob`**

In `render`, store the element indices of each slider's knob + fill + the viewport frame. `previewKnob("width", frac)` sets the width knob center-x and fill width from `frac`; `previewKnob("view", frac)` moves the viewport frame rectangle. Pure element mutation, no `model` call.

- [ ] **Step 2: Rewrite the drag handlers in `interact`**

Width slider (`slide:track`): `mouseDown`/`mouseMove` → compute `frac` from `x`, call `render.previewKnob("width", frac)`, store `pendingRatio`; `mouseUp` → `model.setWidth(win, pendingRatio)` once, then `ctx.afterUpdate()`.
View slider (`scroll:track`) and viewport frame (`vp:frame`): same shape — preview the frame on move, one `model.scrollTo(pendingOffset)` on release.
Remove the per-move `applySlider`/`applyScroll` window writes and the 0.08/0.12s throttles (no longer needed — moves are pure now). Keep the 6s `dragGuard` as a safety net (it now only fires `ctx.afterUpdate`, since nothing to undo).

- [ ] **Step 3: Reload gate + the drag-smoothness test**

Run: `hs -c "hs.reload()"`.
Smoke: drag the width slider across its range — the knob tracks the pointer smoothly with no window resizing until release; on release the focused window resizes once. Same for the view slider and the viewport frame (row scrolls once, on release).
Regression: single clicks on width chips still resize immediately (chips are not drags — unchanged path).

- [ ] **Step 4: Commit**

```bash
git add hammerspoon/.hammerspoon/modules/paperwminteract.lua \
        hammerspoon/.hammerspoon/modules/paperwmrender.lua
git commit -m "perf(paperwm): defer window writes on slider/frame drag to release"
```

---

## Task 7: Phase-1 verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Full pure-test run**

Run: `cd ~/dotfiles/.claude/worktrees/hamerspoon/hammerspoon/.hammerspoon/modules && lua spec/geom_spec.lua`
Expected: all pass, exit 0.

- [ ] **Step 2: Clean-reload check**

Run: `hs -c "hs.reload()"` then inspect `hs.console` — zero errors/warnings from any `paperwm*` module. Toggle tiling off/on (`⌃⌥⌘O`), pin/unpin (`⌃⌥⌘U`) five times each; confirm no leaked canvases (the map is one canvas + the caret) and no runaway timers.

- [ ] **Step 3: Behavior parity checklist**

Walk the whole feature set once and confirm each matches pre-refactor behavior: menubar counter/title, per-column menu, floating return, width chips (incl. blocked/struck-through), stack/unstack, float/unfloat, reorder (chevrons + drag + caret), vertical-drag stack, width slider, view slider, ◀▶ steps, viewport-frame drag, full width, full screen, fit-mode toggle, focus-border toggle, cheatsheet. Note any drift as a bug to fix before Phase 2.

- [ ] **Step 4: No test files tracked**

Run: `git status --porcelain hammerspoon/.hammerspoon/modules/spec/`
Expected: empty output (spec dir is gitignored; nothing staged or tracked).

---

## Self-Review

**Spec coverage (Phase 1 slice):** modularize → Tasks 1–4 (geom/model/interact/render) + Task 2/3 rewiring; "decouple from PaperWM internals" → Task 2 (`model` sole owner); perf #1 canvas reuse → Task 4; perf #3 two-tier → Task 5; perf #2 defer-writes → Task 6. Spec's multi-monitor, all-spaces, per-window, search, thumbnails are explicitly **Phase 2–4** and out of this plan by design (incremental delivery). No Phase-1 requirement is unassigned.

**Placeholder scan:** no "TBD/TODO/handle edge cases"; move-tasks cite exact source line ranges + full new/glue/test code; new logic (canvas reuse, tier, previewKnob, defer-writes) has code blocks.

**Type consistency:** `model.strip()` snapshot shape is the single source for `geom.layout`, `render.draw`, and `interact`; `geom.layout` returns `boxes, floats, totalW, viewport` consistently; `geom.redrawTier` signature changes once (string→`{hash,col}`) in Task 5 with its callers and tests updated in the same task; `interact.isDragging`, `render.canvas`, `render.draw` names match across Tasks 3–6.
