# Phones and tablets

How the shell and every application adapt below desktop widths, which signal to
lay out against, the small set of patterns every app reuses, and what has and
has not been checked.

Written 2026-09-21, after a one-app-at-a-time responsive pass over the
frontend. The brief was to leave the desktop layout unchanged, and every change
below is gated so that a viewport of 1024px or wider renders what it rendered
before — with **two exceptions that changed at every width**: the dock popup
anchoring (§1) and the File Explorer grid icon size (§4).

Standing direction for this work is `CLAUDE.md` §44: desktop is a window-based OS
experience, tablet is an *adaptive application* experience, mobile is a
*mobile-native navigation model*. The platform APIs are shared; only the chrome
and layout differ.

---

## 1. The three tiers

The tier is a property of the **device** — the browser viewport — not of an
application's window.

| Tier | Viewport | Windows | Dock | Apps |
| ---- | -------- | ------- | ---- | ---- |
| Phone | `< 640px` | Every open window is forced maximized. There is no windowed state: every app's `minW` is at least 420px, so a resizable window would always be wider than the screen. | Hidden while any app is open; icons forced to the `sm` size. | One full-screen app at a time; sidebars become drawers, toolbars gain a `⋯` overflow menu. |
| Tablet | `640–1023px` | Windows are not forced maximized but are clamped to the viewport width. | Same as phone: hidden while any app is open. Icons default to `md`. | Same compact patterns as phone, with more room — so fewer things are folded away. |
| Desktop | `≥ 1024px` | Floating, draggable, resizable. Unchanged. | Original behaviour: hidden only while a window covers its strip, revealed by hovering the bottom edge. | Original layouts. |

The 640px boundary is `MOBILE_WINDOW_BREAKPOINT` in `shell/state/systemStore.tsx`
(it is Tailwind's `sm`, and `clampWindowsToViewport()` applies it). The 1024px
boundary is Tailwind's `lg`, used as `isTabletOrNarrower` in `Dock.tsx` and as
`useViewportWidth() < 1024` in applications.

### Why the dock hides differently below 1024px

The desktop dock hides when a window *geometrically covers* its strip and is
revealed by hovering the bottom edge. Neither half works by touch: a tablet
window is not forced maximized, so it can leave the strip uncovered (the dock
stays on top of the app), and there is no hover to bring it back if it did hide.

Below 1024px the rule is therefore keyed to *whether any app is open*, not to
geometry:

| Situation (viewport `< 1024px`) | Dock |
| ------------------------------- | ---- |
| No app open, or every open app minimized | visible |
| Any non-launcher app is open and not minimized | hidden |
| The app is minimized or closed | visible again |
| A dock popup is open (app directory, notifications, clock, overflow) | stays visible |

At `≥ 1024px` the truth table in
[Windows and the dock](shell-windows-and-dock.md#the-complete-truth-table) applies
unchanged. The launcher window never counts as an open app for this rule, same as
on desktop.

The desktop-icon grid and the app drawer follow the dock's icon size at each
tier — `w-8 h-8` on phones, `w-11 h-11` on tablets, and the original `w-10 h-10`
restored from `lg` — so an icon looks the same wherever it appears.

### A change that is not tier-gated: dock popups

The dock's popup panels (notifications, date/clock, overflow) used to anchor to
whichever dock pill opened them. That only stayed on-screen when the pill was
already near the edge, and how near depended on how many apps were pinned and how
wide the viewport was: it ran off the right edge on phones (the report), and was
measured at 4px from doing the same on a 1440px desktop with a fuller dock.

`shell/taskbar/DockPopupPanel.tsx` now anchors to the true screen edge with a flat
12px margin (`left-3` / `right-3`) and is `fixed` rather than `absolute`. That
cannot overflow at any width or dock length, so it replaced the old anchoring at
**every** size rather than only below the reported breakpoint. The consequence is
that on desktop these popups now sit 12px from the screen edge instead of
hovering above their pill — a visible change, made on purpose. If the pill-aligned
desktop placement is wanted back, gate the old classes on `lg:`; the flat margin
must stay below it.

---

## 2. Which signal to lay out against

There are four signals and they answer different questions. Picking the wrong one
was the source of most bugs found during this pass.

| Question | Use | Why |
| -------- | --- | --- |
| "Is this a phone or tablet, as opposed to a desktop with a small window?" | `useViewportWidth()` — `compact = width < 1024`, `phone = width < 640` (`platform/layout/useViewportWidth.ts`) | Default window sizes run from about 520px (Clock) to 1240px (Paint Studio), so most are as narrow as, or narrower than, a phone-sized or landscape-tablet viewport. Comparing the window's own width would put an ordinary desktop window into compact mode. Only the viewport tells the two apart. |
| "Is this window narrow right now?" | `useContainerWidth()` (`platform/layout/useContainerWidth.ts`) or the app's own `ResizeObserver` | A desktop user can drag a window to 420px. That is a window-size question, and it must adapt on desktop too. |
| "Should the phone treatment apply?" for something that only exists at `< 640px` | Tailwind `max-sm:` / `sm:` | Below 640px the window *is* the viewport (forced maximized), so the viewport prefix and the window are the same thing. |
| "Can this device hover?" | `useSupportsHover()` (`platform/layout/useSupportsHover.ts`) | Controls that only appear on hover (tab close buttons) must stay reachable on touch. |

This refines rule 6 of [Windows and the dock](shell-windows-and-dock.md#4-rules-for-changing-this-code),
which still holds for *window-relative* layout: do not use `sm:`/`md:`/`lg:` to
decide what a 400px window on a 1400px screen looks like. It says nothing against
using the viewport to decide *what kind of device this is*, which is what
`useViewportWidth` is for.

Some apps deliberately use both signals, each for its own question. Word Book
folds its ribbon to a short set of controls by viewport, but drops the title
bar's secondary text by the window's own measured width. Paint Studio auto-fits
its canvas by viewport and moves its side panels into overlays by container
width.

**Tailwind 4's `dark:` follows the operating system, not the app's theme.** A
compact-mode surface that must match the app's own light/dark choice takes its
colours from the theme object already in scope, not from `dark:` classes.

---

## 3. Shared building blocks

| Piece | Location | What it is |
| ----- | -------- | ---------- |
| `useViewportWidth` | `platform/layout/useViewportWidth.ts` | Live `window.innerWidth`, for device-class decisions. |
| `useContainerWidth` | `platform/layout/useContainerWidth.ts` | Width of the element itself (`ResizeObserver`). Pre-existing. |
| `useSupportsHover` | `platform/layout/useSupportsHover.ts` | Whether the primary input can hover. Pre-existing. |
| `SelectMenu` | `design-system/components/SelectMenu.tsx` | A dropdown whose list is drawn inside the app. Opens downward, or upward when there is more room above; `maxHeight ≤ 224px`; closes on outside tap; `role="listbox"` / `role="option"`. Takes `menuClassName` so the host app supplies its own surface colours. |

### The patterns

Every application reuses the same handful of moves. New work should pick from
this list rather than invent another.

1. **Sidebar → overlay drawer.** `absolute inset-y-0 left-0 z-30 w-72 max-w-[85%] shadow-2xl`
   over a `absolute inset-0 z-20 bg-black/40` backdrop; the parent must be
   `relative`. It closes on item select, on backdrop tap, and through a visible
   control — a toggle must close the drawer on the second tap, and where the open
   drawer covers its own toggle it carries an explicit close (X) button.
2. **Toolbar that does not fit → `⋯` overflow menu**, not wrapping. Wrapping puts
   an unevenly-spaced second row on screen; horizontal scrolling with a hidden
   scrollbar clips the last item with no hint it exists. The most-used controls
   stay in the row; the rest go in the menu.
3. **Labelled tabs → icon-only** when there is no room for the label (Clock,
   Calculator, PDF annotation tools). Keep `title` and `aria-label`.
4. **Multi-pane → single pane.** A list/detail pair shows one at a time with an
   explicit back control (Messages, Mail).
5. **Native `<select>` → `SelectMenu`.** The browser positions a native popup
   itself, and on a phone it can open partly or wholly off-screen. This was
   reported on the PDF zoom control and then fixed everywhere it occurred.
6. **Fixed-pixel content → auto-fit zoom** (Word Book pages, Paint canvas), so the
   whole page is visible instead of demanding horizontal scroll. Recomputed when
   the *available* width changes, not on every zoom change, so a manual zoom is
   not immediately undone.
7. **Modals → full-bleed on phones** (`p-0 sm:p-6`, `rounded-none sm:rounded-2xl`)
   and `max-w-full` instead of a fixed pixel width.
8. **Touch drawing → Pointer Events**, with `touchAction: 'none'` on the surface.
   Mouse-only handlers leave a finger drag scrolling the page (PDF ink, Meet
   whiteboard).

### Four traps

* **Click-outside listeners must run in the capture phase.** The window shell
  stops propagation of pointer and click events that start inside a window, so a
  bubbling `document.addEventListener('pointerdown', …)` never fires for a tap on
  the app's own content. Use `document.addEventListener('pointerdown', h, true)`.
  This broke four separate outside-tap closers before it was understood.
* **An overlay needs a positioned parent.** `absolute inset-y-0` with no
  `relative` ancestor anchors to the window and covers the title bar.
* **Arbitrary z-index needs brackets** in Tailwind 4 (`z-[25]`); a bare `z-25`
  generates nothing.
* **Hover-only controls vanish on touch.** A tab's close button that appears on
  hover needs an `alwaysShow` path when `useSupportsHover()` is false.

---

## 4. What each application does

`compact` is `< 1024px` and `phone` is `< 640px` unless stated. Desktop is
unchanged in every row except the two called out under the table.

| App | Phone / tablet behaviour |
| --- | ------------------------ |
| Shell | Dock hidden while an app is open; icon sizes per tier; dock popups anchored to the screen edge so they always fit (all widths — see §1). |
| File Explorer | Sidebar becomes a menu-triggered drawer with a directly visible toggle (also a View-menu item); drawer closes after navigation; grid-view icons are smaller (**at every width** — see below). |
| Clock | Tab row drops to icon-only below a narrow window width (container-measured). |
| Calendar | Five view buttons collapse to one dropdown below a very narrow window width. |
| Calculator | Mode tabs become icon-only; History becomes an overlay drawer instead of sharing the row. |
| Word Book | Ribbon shows a short set of common controls plus a "More options" menu; pages auto-fit-zoom to the available width; title bar drops secondary text so the filename keeps its width. |
| Paint Studio | Canvas auto-fits; Tools and Properties panels are overlay drawers with a backdrop rather than shrinking the canvas; a custom colour picker (`PaintColorPicker.tsx`) replaces one that opened off-screen. |
| Settings | Category sidebar is a drawer opened from the header; sub-tab pills are measured, and those that do not fit move into a `⋯` "More tabs" menu (never wrapping, never clipped); the active tab always stays in the row. |
| Trash Bin | Three-column rows fold the type under the name; the size figure only claims what it can account for. |
| Contacts | Groups/labels sidebar becomes a drawer (Menu button, `aria-label="Open groups and labels"`); the chip strip collapses to All / Favourites plus the active label. |
| PDF Viewer | Sidebar is an overlay drawer, closed by default; two-row toolbar with `⋯` "More actions"; annotation tools icon-only on phones; zoom is a custom `ZoomDropdown` (desktop keeps the native select); ink uses Pointer Events. |
| Mail Studio | Mailboxes sidebar is a drawer; list and reader are single-pane; toolbar search and pills hidden; reader actions reduce to Reply / Reply All / Trash plus `⋯`; the sidebar toggle opens *and* closes. |
| Messenger | Conversation list is the home screen with a "‹ Chats" back button; contact and group details are overlay panels; per-message menu and reaction strip flip left/right/up to stay inside the window. |
| Editor | Activity bar and inline sidebar are replaced by one Explorer/Search/Settings drawer opened from a Files button in the tab bar; 40px tree rows; minimap off; Settings page category nav becomes a dropdown on phones. |
| OSX Meet | Whiteboard is full-screen with an icon-only header and finger drawing; Breakout Rooms, Invite and Schedule modals fit 360px; camera, microphone, meeting-time and category selects are `SelectMenu`. The in-call control bar wraps to two rows on phones. |

**The two changes that are not tier-gated.** Everything above applies below 1024px
only, except: (1) dock popup anchoring (§1), and (2) the File Explorer grid-view
file icon, which `renderFileIcon(item, 'large')` shrank from `w-10 h-10` (40px) to
`w-8 h-8` (32px) with no viewport condition, so it is also smaller on desktop. The
request that produced it ("icon size of folders and other types should be a little
smaller") was made alongside the phone/tablet sidebar work and does not say whether
desktop was meant to change. List-view (`small`) and the properties-panel (`xl`)
icons are unchanged. To make it phone/tablet-only, gate the `large` size on
`isMobileOrTabletView` inside `renderFileIcon`.

### Not done

| App | State |
| --- | ----- |
| Spreadsheet, Presentation, Browser, Terminal, Launcher app | **Not touched.** They render at desktop layout on every tier. |

### Known gaps left on purpose

* **PDF text layer** — the text-layer spans scale incorrectly at every size, not
  only on phones. It predates this work and was not changed.
* **File Explorer folder picker** — the search input in the "open from Drive"
  picker extends past the right edge at 390px.
* **OSX Meet** — the in-call layout was only exercised with one participant, so a
  multi-participant grid on a phone is unchecked. Screen sharing and real device
  cameras/microphones are also unchecked.

---

## 5. Verification status

| Claim | Basis |
| ----- | ----- |
| Each application listed in §4 renders inside the viewport, and its drawers, overflow menus and dropdowns open, select, and close | `VERIFIED (LIVE)` — driven in Chromium through Playwright at phone widths (360 and 390px) and tablet width (768px), with off-screen element scans (`getBoundingClientRect().right > innerWidth`) and reviewed screenshots. OSX Meet's matrix is exactly 360 / 390 / 768 / 1440px; the earlier apps were checked at the same phone and tablet widths but their matrices were not recorded so precisely. The shell, File Explorer, Clock, Calendar, Calculator, Word Book, Paint Studio, Settings and Trash Bin were done in the first part of the work; their check scripts were not kept, so the record for those rests on the working notes of that session rather than on artefacts you can inspect. |
| Desktop layout is unchanged | `VERIFIED (LIVE)` for OSX Meet at 1440px (pre-meeting selects present, in-call Leave button at the same position as baseline, no off-screen elements). For the other apps this was checked by gating every change on the tier, and by review, not by a pixel comparison. **Exceptions:** the dock popup anchoring (§1) and the File Explorer grid icon size (§4) changed on desktop, and neither's desktop appearance was compared against the old one. |
| Finger drawing (PDF ink, Meet whiteboard) | `VERIFIED (LIVE)` for the whiteboard by pointer-drag through Playwright (canvas went from 0 to 2,853 non-white pixels). This is emulated pointer input, **not a real touchscreen**. |
| Production build | `VERIFIED (BUILD)` — `npx vite build` passed after the last edit. |
| Typecheck | `UNKNOWN` — `tsc --noEmit` crashed in this session's environment, so `vite build` was the compile check. The crash was pre-existing and its cause was not investigated. |
| Behaviour on a real phone or tablet — iOS Safari, Android Chrome, on-screen keyboard, rotation, safe-area insets, real touch gestures | `UNKNOWN` — never run on hardware. Emulated viewports do not reproduce the browser's dynamic toolbar, the on-screen keyboard resizing the viewport, or touch-only hover semantics. |
| The tier signals themselves (`useViewportWidth`, the dock rule) | `REVIEWED` — no unit tests. The frontend has no test runner (TASK-014). |

The Playwright scripts used for this pass lived in a session scratchpad, not in
the repository, so **none of it is re-runnable from a checkout** and there is no
regression coverage for any of it. That is the same gap as TASK-014 and it is the
main risk here: a later edit can silently break a drawer or push a toolbar off the
edge again, and nothing will fail.

---

## 6. Rules for changing this code

1. **Decide the question first** (§2). If it is "phone or desktop", use the
   viewport; if it is "narrow window", measure the window.
2. **Gate every compact-only change** on `compact`/`phone` so a ≥1024px viewport
   renders exactly what it did before. If you cannot show that, the change is not
   done.
3. **Do not wrap a toolbar to make it fit.** Use the overflow menu (§3, pattern 2).
4. **Do not add a native `<select>`** to anything reachable on a phone. Use
   `SelectMenu`.
5. **Attach outside-tap handlers in the capture phase** (§3, traps).
6. **Every overlay needs three exits**: item select, backdrop tap, and a visible
   control. Verify the toggle closes it on the second tap.
7. **Verify by driving it.** Check at 360, 390, 768 and 1440px, scan for elements
   past `innerWidth`, and open every menu and dropdown — a popup can be
   in-bounds when closed and off-screen when open.
8. **Do not restate the breakpoints.** 640 lives in `systemStore.tsx`
   (`MOBILE_WINDOW_BREAKPOINT`) and 1024 in `useViewportWidth`'s callers; do not
   introduce a third number without a reason.

---

## 7. Where the code is

| Concern | File |
| ------- | ---- |
| Force-maximize below 640px, tablet clamp | `shell/state/systemStore.tsx` (`MOBILE_WINDOW_BREAKPOINT`, `clampWindowsToViewport`) |
| Dock hiding below 1024px, dock icon sizes | `shell/taskbar/Dock.tsx`, `shell/taskbar/DockPopupPanel.tsx` |
| Desktop and app-drawer icon sizes | `App.tsx`, `shell/launcher/ApplicationMenuPopup.tsx` |
| Viewport, container and hover signals | `platform/layout/` |
| In-app dropdown | `design-system/components/SelectMenu.tsx` |
| PDF zoom dropdown | `apps/pdf-viewer/components/Toolbar.tsx` (`ZoomDropdown`) |
| Mail `⋯` menu | `apps/mail-studio/index.tsx` (`ActionMenu`) |
| Settings measured tab pills | `apps/settings/index.tsx` |
| Paint colour picker | `apps/paint-studio/components/PaintColorPicker.tsx` |
| Word Book compact ribbon | `apps/wordbook/components/ribbon/RibbonToolbar.tsx` (`RibbonMoreMenu`) |
