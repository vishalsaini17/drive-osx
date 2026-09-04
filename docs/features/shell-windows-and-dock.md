# Windows and the dock

How a window is moved and resized, and how the dock decides whether to be on
screen. These two are one topic because they are coupled: the dock reacts to
where windows are, including while a window is still being dragged.

Read this before changing anything in `shell/window-manager/` or
`shell/taskbar/`. The behaviour looks simple and the obvious implementation of
it is wrong in a way that took down the whole desktop once already.

---

## 1. The rule that governs everything here

> **A pointer gesture must not write to the system store while the pointer is
> down.**

`systemStore` owns `windows`, and every mutation replaces the whole array. Six
components subscribe to it — the dock, the launcher, the terminal, `App.tsx`,
`WindowStatusBar`, and every open `AppWindow`. Committing a window's position
on each pointer move therefore re-renders the entire desktop sixty times a
second.

That is not merely slow. Effects keyed on `windows` re-run on every one of
those renders, and several of them call `setState` with freshly allocated
arrays — a new array is a new value to React even when it holds the same
contents. React never reaches a settled commit, its nested-update counter
climbs, and at fifty it throws:

```
Uncaught Error: Maximum update depth exceeded.
    at handleMouseMove (Dock.tsx:245)
```

The stack trace names whichever handler dispatched last, which is almost never
the cause. In the reported case it accused the dock's `mousemove` listener; the
actual culprit was `onMove` being called from the window title bar.

---

## 2. How a gesture works

`AppWindow` runs drag and resize through one small state machine.

```text
pointerdown  →  snapshot geometry, take pointer capture, gesture = drag|resize
pointermove  →  update a ref, schedule one animation frame
    (frame)  →  write transform / width / height straight to the element
             →  report the window's bottom edge to the dock
pointerup    →  clear the transform, commit once to the store, gesture = settling
    (frame)  →  gesture = idle
```

Everything mid-gesture lives in refs and in the DOM. The store learns the
result exactly once, on release.

| Concern | How it is handled |
| ------- | ----------------- |
| Position | A `transform`, so the browser can move the window on the compositor rather than laying the page out again. |
| Size | `width` / `height` written directly; a resize genuinely needs layout. |
| Event rate | Coalesced into one `requestAnimationFrame`, so a burst of pointer events costs one style write. |
| Interruption | `pointercancel` takes the same path as `pointerup`. Without it an alt-tab mid-drag would strand the window under a stale transform. |
| Unmount | A queued frame is cancelled and the dock gesture is ended, so closing a window mid-drag leaves nothing behind. |

### Two traps in the commit

Both of these are already encoded in the code with comments. They are repeated
here because both look like unrelated bugs when they bite.

**Clear only what React does not manage.** React writes a style property only
when *its own* value for it changed. After a drag, React's `width` is
unchanged, so clearing the inline `width` would leave the element with no width
at all — React will not rewrite a value it believes is already applied. Only
`transform` is cleared, because React never sets it.

**A gesture ends in a `settling` render.** The window has a
`transition-[top,left,width,height]` for maximize and restore. Re-enabling that
transition in the same commit that moves `top`/`left` starts a transition, so
the window would slide from where the drag began to where it was dropped, 150ms
after the user let go. `settling` keeps the transition off for the commit render
and drops to `idle` one frame later.

### Clamping

The title bar must stay reachable, so a drag clamps the window's top edge to
`viewportHeight − dockDeduction − 36`. The window *body* is free to extend
behind the dock; only the title bar is kept clear. Dragging a **maximized**
window is a no-op — it fills the screen and has no position to change.

Note that the clamp constants (`52`/`78`/`92`) are deliberately not the same as
the dock zone measurements below (`60`/`82`/`95`). The clamp reserves room for
the title bar; the zone describes what the dock visually occupies.

---

## 3. Dock visibility

The dock hides itself whenever a window occupies its strip of the screen, and
reveals itself while the cursor is at the very bottom edge. A maximized
application is not a special case in the implementation — it is simply the case
where "a window covers the dock" is permanently true.

`shell/taskbar/dockZone.ts` owns the measurement:

| Dock size | Strip height |
| --------- | ------------ |
| `sm` | 60px |
| `md` (default) | 82px |
| `lg` | 95px |

A window covers the strip when `window.y + window.h > viewportHeight − stripHeight`.
A window resting exactly on the boundary does **not** count as covering it.

### The complete truth table

| Situation | Dock |
| --------- | ---- |
| No windows, or none reaching the strip | visible |
| A window is maximized | hidden |
| A window was dropped over the strip | hidden |
| A window is being dragged into the strip, pointer still down | hidden immediately |
| A window is being dragged back out, pointer still down | revealed immediately |
| Cursor within 10px of the bottom edge, in any hidden state above | revealed |
| Cursor moves back above the strip + 15px | hidden again |
| A dock popup is open (app directory, notifications, clock, overflow) | stays visible |
| The covering window is minimized or closed | visible |
| The launcher window covers the strip | ignored — the launcher never hides the dock |

The 15px difference between the reveal threshold (bottom 10px) and the hide
threshold (strip + 15px) is deliberate hysteresis: without it the dock would
flicker as the cursor moved onto the dock it had just revealed.

### How the dock sees a drag in progress

A gesture does not reach the store until release, so nothing reading `windows`
can tell where a window is mid-drag. Rather than reintroduce a per-frame store
write, `AppWindow` publishes the single fact the dock needs to a dedicated
store in `dockZone.ts`:

```ts
{ gestureWindowId: string | null, gestureCoversDock: boolean }
```

Two properties of this make it safe:

**It replaces, rather than supplements, the stored position — for that one
window only.** The dock evaluates `gestureCoversDock` *instead of* the stored
`y + h` when the window being tested is the one under the pointer. An earlier
version OR'd the two together, which produced the mirror-image bug: dragging a
window up and out of the strip left the dock hidden until release, because the
stored position still overlapped. Every other window is still judged from the
store, so a second window parked over the dock keeps it hidden regardless of
what is being dragged.

**An unchanged report is a no-op.** The store returns its current state when
neither field changed, and Zustand skips notification entirely when `setState`
returns the same object. A drag can therefore report on every frame and only
costs a render on the frame the window crosses the line.

`endGesture` is guarded by window id, so a window unmounting long after its own
gesture ended cannot cancel someone else's.

---

## 4. Rules for changing this code

1. **Never call a store action from a `pointermove` handler.** If a gesture
   needs to be visible somewhere else while it runs, publish the one derived
   fact — as `dockZone.ts` does — rather than the geometry.
2. **Do not depend on the `windows` array in an effect** unless the effect
   genuinely cares about geometry. Depend on a signature of the fields you read.
   `App.tsx` routing keys on `id:isOpen`; the dock keys on ids alone.
3. **Guard `setState` that rebuilds an array.** `setDockAppOrder(newArray)` is a
   state change even when the ids are identical. Compare first.
4. **Do not restate the dock strip's height.** Import `dockZoneHeight` /
   `coversDockZone`. Those numbers were previously written inline in three
   places with two different sets of values.
5. **`focusWindow` is a no-op when the window already has focus.** Every pointer
   press inside a window asks for focus; without the guard each one replaced the
   whole array and replayed the click sound to reach the state it was already in.
6. **Applications must not lay out against Tailwind's `sm:`/`md:`/`lg:`
   prefixes.** Those measure the browser viewport, which here is the whole
   desktop — a 400px window on a 1400px screen still matches `md:`. Use
   `platform/layout/useContainerWidth.ts`, which observes the element itself.
   The Contacts detail pane was fixed this way; thirteen applications still
   carry the latent bug, tracked as TASK-025 in
   [the audit](../status/audit-and-plan.md).
7. **Watch hook order.** There is no ESLint in this repository, so
   `react-hooks/rules-of-hooks` never runs. A hook placed after an early
   `return null` crashes the whole tree — this is exactly how right-clicking the
   desktop produced a white screen.

---

## 5. Verification status

Per the honesty rules in [the developer guide](../guides/developer-guide.md),
here is precisely what has and has not been checked.

| Claim | Basis |
| ----- | ----- |
| Gesture arithmetic — clamping at all four edges, all three dock sizes, minimum sizes | `VERIFIED (TEST)` — the state machine is transcribed into a headless suite and exercised |
| One store commit per gesture, regardless of pointer event count | `VERIFIED (TEST)` — a 120-event drag produces exactly one commit |
| Dock visibility truth table above | `VERIFIED (TEST)` — every row is an assertion against the real `dockZone` module |
| The live-gesture store does not notify on unchanged reports | `VERIFIED (TEST)` — 120 identical reports produce zero notifications |
| Typecheck and production build | `VERIFIED (BUILD)` |
| That dragging *feels* smooth, and the dock animates cleanly | `UNKNOWN` — there is no browser automation in this repository. Resolved by a human dragging a window, or by the harness proposed in [TASK-014](../guides/testing.md). |

The suites live in the scratchpad rather than the repository because
`drive-osx-ui` has no test runner. Standing up one is TASK-014; until then
these checks must be re-run by hand and their absence from CI is a real gap,
not an oversight.

---

## 6. Where the code is

| Concern | File |
| ------- | ---- |
| Gesture state machine, clamping, commit | `shell/window-manager/AppWindow.tsx` |
| Dock strip measurement + live-gesture store | `shell/taskbar/dockZone.ts` |
| Visibility decision, reveal-on-hover, dock rendering | `shell/taskbar/Dock.tsx` |
| Window geometry, focus, maximize/minimize | `shell/state/systemStore.tsx` |
| Container-width measurement for applications | `platform/layout/useContainerWidth.ts` |
