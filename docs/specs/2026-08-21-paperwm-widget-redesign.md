# PaperWM widget — modularize, de-lag, extend

**Date:** 2026-08-21
**Status:** Design (awaiting review)
**Scope:** `hammerspoon/.hammerspoon/modules/paperwm*.lua` + `winjump.lua` integration
**Unchanged:** `paperwmfit.lua` engine, `paperwm.lua` hotkeys, `init.lua` public API, `focusborder.lua`

## Problem

`paperwmui.lua` is a single 1234-line module doing three jobs at once — reading
PaperWM state, drawing the canvas, and handling all mouse/drag interaction. It is
hard to extend and it lags in three ways the user named:

1. **Whole-overlay rebuild.** `M.draw()` calls `M.canvas:delete()` +
   `hs.canvas.new()` + full `appendElements(...)` on *every* change. This flickers,
   is expensive, and destroys mouse-tracking mid-interaction (hence the 6s
   `dragGuard` timers that exist only to recover from a teardown landing mid-drag).
2. **Slider/frame dragging stutters.** Every drag step runs the full mutation
   chain `setWidth → moveWindow → tileSpace → refit → afterChange`, i.e. multiple
   Accessibility writes + a queued redraw *per mouse-move event*.
3. **General sluggishness.** Every window event triggers a full relayout even when
   only the focus highlight moved; strip reads do per-window Accessibility
   round-trips.

The widget is also tightly coupled to this one machine and PaperWM's private state:
hardcoded cheatsheet path, single-screen math, direct `pwm.state.*` / `pwm.floating.*`
calls scattered throughout, no multi-monitor or multi-space awareness.

## Goals

- **Modularize** the 1234-line file into small, single-purpose units.
- **De-lag** on all three fronts above.
- **Universal:** multi-monitor (incl. moving windows between monitors from the
  widget), all-spaces overview, remove hardcoded assumptions, decouple from
  PaperWM internals, make it robust.
- **Features:** window search/jump (extend existing `winjump.lua`), per-window
  controls inside stacked columns, live thumbnails.

## Non-goals

- Keyboard-driven widget navigation (not requested).
- Rewriting `paperwmfit.lua` or the PaperWM.spoon.
- Supporting window managers other than PaperWM.spoon.

## Architecture

Split `paperwmui.lua` into four modules. **Exactly one file** (`paperwmmodel`) is
allowed to touch PaperWM internals — that is the decoupling boundary.

```
  init.lua ──> paperwmui.lua        thin coordinator: menubar, lifecycle, pin/flash
                    │
        ┌───────────┼────────────┐
        ▼           ▼            ▼
  paperwmmodel  paperwmrender  paperwminteract
        │
        ▼
   paperwm.pwm / paperwmfit
```

### `paperwmmodel.lua` — the only PaperWM adapter

The single owner of `pwm.state.*`, `pwm.floating.*`, `pwm.windows.*`, and
`paperwmfit`. Everything else talks to this API only. Two halves:

**Reads** (return plain Lua tables, never PaperWM objects except window handles):

- `model.strip(opts)` → snapshot of the focused space+screen:
  `{ columns = { { wins, ratio, vx, px } … }, floating, col, total, space, screen, canvas, left, stripW }`
  (this is today's `computeStrip`, moved and extended with `screen`).
- `model.screens()` → list of screens with their strips (for multi-monitor draw
  placement and the "→ screen N" drop zones).
- `model.spaces(screen)` → per-space strips for the all-spaces overview. Non-current
  spaces are built **cheaply** from PaperWM's virtual x-positions + last-known
  widths (no live Accessibility frame reads).
- Strip cache (today's 0.25s TTL) lives here; `model.invalidate()` clears it.

**Writes** (the mutation chain, today scattered as `setWidth`, `moveColumnTo`,
`toggleFloat`, `scrollTo`, `fullWidth`, `toggleFullWidth`, `toggleFullscreen`,
slurp/barf):

- `model.setWidth(win, ratio)`, `model.moveColumn(space, from, to)`,
  `model.toggleFloat(win)`, `model.scrollTo(space, offset)`,
  `model.stack(win)` / `model.unstack(win)`, `model.moveToScreen(win, screen)`.
- Each returns after issuing writes; the coordinator decides when to redraw.

### `paperwmrender.lua` — snapshot → canvas

Owns geometry (`layout`), element building, and the **anti-lag rendering core**. No
`pwm.*` calls. Renders from a model snapshot into a **persistent, reused canvas**.

- **Reuse the canvas** (mirror `focusborder`): create the `hs.canvas` once; on
  redraw call `canvas:replaceElements(els)` (or index-assign the changed elements),
  never `delete()`+`new()`. Rebuild the canvas object *only* when its target
  screen/frame changes.
- **Two redraw tiers:**
  - *cheap* — only the focus highlight moved: restyle the two affected column boxes
    (`fillColor`/`strokeColor`) in place.
  - *full* — column count / order / widths / floating set changed: rebuild the
    element list and `replaceElements`. A small hash of `{col, order, widths,
    floatIds}` from the snapshot decides which tier to run.
- The drop caret stays a separate canvas (as today) so a drag never rebuilds the map.

### `paperwminteract.lua` — mouse/drag/gesture → model commands

Owns the `mouseCallback`, hit-testing (`columnAt`, chip/slider geometry), and drag
state. Translates gestures into `model` calls. Key change:

- **Drags write to windows at most once, on release.** During a slider / view /
  frame drag, `interact` updates only the *widget's own* visual (moves the knob or
  the viewport frame via `render`'s in-place update) and stores the pending target.
  The real `model.setWidth` / `model.scrollTo` fires once on `mouseUp`. Optional
  "live" mode: throttle real writes to ≤1 per 100ms. This removes the per-mouse-move
  mutation chain that causes the drag stutter.
- Column reorder, vertical-drag stack/unstack, per-window row clicks route here.

### `paperwmui.lua` — coordinator

Keeps the public API used by `init.lua` unchanged: `start`, `show`,
`toggleFullWidth`, `toggleFullscreen`. Owns the menubar, the shared-filter
subscription, pin/flash lifecycle, and wires `model → render → interact`. Replaces
today's per-mutation redraw timers with one coalesced "apply then redraw" path.

## Feature designs

### Multi-monitor + robustness

- Add `hs.screen.watcher` (like `focusborder`) → re-place / rebuild the widget
  canvas on layout change.
- Draw on the focused window's screen; fall back to screen-under-mouse, then main.
- Cross-screen move: dragging a column box onto a **"→ screen N"** drop zone calls
  `model.moveToScreen(win, screen)`. Drop zones appear only when >1 screen.
- Robustness: all `pwm.*` behind `model`; nil-focus fallbacks kept; stale-id pruning
  kept; canvas reuse removes the mid-drag-teardown failure mode.

### Per-window controls

Rows inside a stacked column become individually hit-testable
(`id = "win:<winid>"`): click focuses that specific window; per-window float /
unstack. `model` already holds each window handle; change is render (draw row
sub-boxes with ids) + interact (route `win:` ids).

### Window search/jump — extend `winjump.lua`, do not duplicate

`winjump.lua` already provides a cross-space fuzzy chooser. Integrate:

- The widget exposes a search affordance (a chip in pinned mode + the existing
  `⌃⌥⌘Space` hotkey) that calls `winjump.show()`.
- `winjump` draws its window list from `model` (one source of truth for the window
  set) instead of calling `pwm.window_filter` directly.
- Extend the chooser action: a chosen window can be **focused** (default) or, with a
  modifier / a second action, **pulled into the current column** (`model.stack` after
  focus) or **returned from floating** (`model.toggleFloat`).

### Live thumbnails (gated for perf — confirmed)

- `hs.window.snapshot(id)` per window is a screencapture; live-every-redraw would
  reintroduce lag. Therefore: **pinned mode only**, cached per window as an
  `hs.image`, refreshed lazily (on focus / hover, throttled to once per N seconds
  per window), **suspended during drags**. Drawn as an image element that persists
  across redraws thanks to canvas reuse. Off when unpinned.

### All-spaces overview (opt-in — confirmed)

- A toggle (menubar item + optional hotkey). When on, `render` draws one strip row
  per space on the current screen; the current space is highlighted and fully
  actionable. Non-current spaces render cheaply from `model.spaces()` (virtual
  x-positions + last-known widths, no live AX). Acting on a non-current space
  switches to it first. Off by default.

## Delivery phases

Each phase is independently shippable; behavior after phase 1 is unchanged.

1. **Modularize + perf** — split into 4 modules; canvas reuse + `replaceElements`;
   two-tier redraw; drags write once on release. No behavior change, just faster.
2. **Multi-monitor + robustness** — screen watcher, screen-aware placement,
   "→ screen N" drop zone, `model.moveToScreen`.
3. **Per-window controls + winjump integration** — per-window row hit-testing;
   `winjump` sources from `model` and gains pull-into-column / unfloat actions.
4. **All-spaces overview + thumbnails** — the two perf-gated extras, last.

## Testing / verification

Hammerspoon UI is not unit-testable end-to-end, so verification is layered:

- **Pure model functions** (hash, layout math, `columnAt`, offset clamping,
  cheap-vs-full decision) are extracted to be callable without a live canvas and
  exercised from the Hammerspoon console with a stub `pwm` table.
- **Manual smoke per phase**, reloaded via `hs.reload()`:
  - P1: focus-hop across a 6+ window strip shows no flicker; drag the width and
    view sliders — smooth, one window move on release; menubar counter correct.
  - P2: move a window to another monitor via the drop zone; unplug/replug a monitor
    → widget re-places itself.
  - P3: click a specific window in a stacked column focuses it; search → pull into
    column.
  - P4: toggle all-spaces (non-current spaces render without stutter); thumbnails
    appear only when pinned and don't reintroduce drag lag.
- Watch `hs.console` for errors; confirm no leaked timers/canvases after toggling
  pin and tiling on/off repeatedly.

## Risks

- **Snapshot cost** — mitigated by pinned-only + throttle + drag-suspend; if still
  heavy, fall back to app-icon tiles (current behavior).
- **Non-current-space reads** — if virtual positions drift from reality, the
  all-spaces rows are approximate; acceptable because acting switches to the space
  first (which does a live read).
- **`replaceElements` + live mouse tracking** — must verify tracking survives
  element replacement mid-hover; `focusborder`'s reuse pattern is the precedent.
