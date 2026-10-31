# UI wireframes, theme architecture and UX workflow

The screen layout of the Drive OSX shell, how theming is built, and the user
journeys through the interface.

Written 2026-10-07 from the code in `drive-osx-ui/src`. The wireframes are
schematic ASCII, not pixel measurements. Where the code and the design tokens
disagree, §2.5 says so.

Related: [Windows and the dock](shell-windows-and-dock.md) (window mechanics),
[Phones and tablets](responsive-layout.md) (tiers and per-app compact behaviour),
`CLAUDE.md` §3, §7, §8, §20, §43, §44.

---

## 1. Wireframes

### 1.1 Screen map

```text
/login  /register  /forgot-password  /reset-password      unauthenticated
/s/:token                                                  public share link
        │
        ▼ (authenticated)
/   /folder/:folderId   /meeting/:meetingId   /:appRoute   DesktopLayout
        │
        └── Wallpaper + Desktop icons + Windows + Dock + Top bar
```

Every authenticated route renders the same `DesktopLayout`; the URL only decides
which window opens on load (File Explorer for `/folder/…`, OSX Meet for
`/meeting/…`, the matching app for `/:appRoute`). Unauthenticated visitors are
redirected to `/login?next=<intended path>`; after sign-in only a same-origin
relative `next` is followed.

### 1.2 Desktop (≥ 1024px)

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ Top bar                                                                  │
│ [Desktop 1 ▾]                                      [Wi-Fi][Vol][Battery] │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────┐                         Wallpaper                                │
│  │icon│ Desktop icons          ┌─────────────────────────────────┐       │
│  │ 📁 │ (Files, Paint,         │ ● ● ●   Window title        ─ □ ✕│      │
│  └────┘  Messenger, …)         ├─────────────────────────────────┤       │
│  ┌────┐                        │ Menu bar  File Edit View Window │       │
│  │ 🗑 │                        ├─────────────────────────────────┤       │
│  └────┘                        │                                 │       │
│                                │        Application content      │       │
│                                │                                 │       │
│                                ├─────────────────────────────────┤       │
│                                │ Status bar                      │       │
│                                └─────────────────────────────────┘       │
│                                                                          │
│                ┌──────────────────────────────────────┐                  │
│                │ [▦] [app] [app] [app] [app] [⋯] [🔔][🕐]│  ← Dock        │
│                └──────────────────────────────────────┘                  │
└──────────────────────────────────────────────────────────────────────────┘
```

| Region | Component | Notes |
| ------ | --------- | ----- |
| Top bar | `shell/taskbar/TopBar.tsx` | Workspace switcher on the left; Wi-Fi, volume, battery dropdowns on the right. Tinted from the wallpaper's tone, not a fixed dark film. |
| Wallpaper | `shell/desktop/Wallpaper.tsx` | 21 wallpapers; each declares a `tone` (light/dark) so desktop labels stay readable. |
| Desktop icons | `App.tsx` `DesktopLayout` | The set is stored under `desktop-shortcuts` (default: Files, Paint, Messenger); edited in Settings → Desktop. |
| Window | `shell/window-manager/AppWindow.tsx` | Title bar with controls, optional menu bar (`WindowMenu`), content, optional status bar (`WindowStatusBar`). Draggable and resizable. |
| Dock | `shell/taskbar/Dock.tsx` | Launcher, pinned and running apps, **More Apps** overflow, calendar/clock and system/notification panels. |
| Dock popups | `shell/taskbar/DockPopupPanel.tsx` | Application menu, More Apps, notifications, calendar/clock. Anchored to the screen edge. |
| Context menu | `shell/context-menu/GlobalContextMenu.tsx` | One global menu; long-press opens it on touch. |
| Toasts / sync | `SystemToastNotifier`, `SyncStatusIndicator` | Rendered once in `App`, above everything else. |

### 1.3 Application menu (launcher)

```text
┌─────────────────────────────────────────────┐
│ [🔍 Search apps and files                 ] │
├─────────────────────────────────────────────┤
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐    │
│  │Files│ │Mail │ │Docs │ │Sheet│ │Slides│   │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘    │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐    │
│  │Paint│ │Meet │ │Chat │ │ PDF │ │ ... │    │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘    │
└─────────────────────────────────────────────┘
        (scrim over the desktop behind it)
```

Implemented by `shell/launcher/ApplicationMenuPopup.tsx` and
`MoreAppsPopup.tsx`. The catalogue is `apps/index.ts` (20 lazily loaded apps).

### 1.4 A typical application window: File Explorer

```text
┌────────────────────────────────────────────────────────────┐
│ ● ● ●  Files                                          ─ □ ✕│
├────────────────────────────────────────────────────────────┤
│ File  Edit  View  Window  Help                             │
├──────────┬─────────────────────────────────────────────────┤
│ Sidebar  │ [‹][›] / Home / Projects        [🔍][▦ ≡]       │
│ ───────  ├─────────────────────────────────────────────────┤
│ Home     │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐             │
│ Drive    │ │folder│ │folder│ │ file │ │ file │             │
│ Shared   │ └──────┘ └──────┘ └──────┘ └──────┘             │
│ Trash    │                                                 │
├──────────┴─────────────────────────────────────────────────┤
│ 4 items · 2 selected                       ● Synced        │
└────────────────────────────────────────────────────────────┘
```

Most apps follow this skeleton: **title bar → menu bar → (sidebar | content) →
status bar**. The shared pieces are `design-system/components/AppShell.tsx`,
`AppToolbar.tsx`, `SearchInput.tsx`, `SelectMenu.tsx`, `Modal.tsx`, `Badge.tsx`,
`EmptyState.tsx` and `ToggleSwitch.tsx`. The standard Window and Help menus come
from `shell/window-manager/standardMenus.ts` (New Window, Minimise, Maximise,
Bring to Front, Switch To, Close Window, Keyboard Shortcuts, Help, About).

### 1.5 Phone (< 640px)

```text
┌──────────────────┐        ┌──────────────────┐
│ Top bar          │        │ ☰  App title  ⋯  │  ← one app, full screen
├──────────────────┤        ├──────────────────┤
│                  │        │                  │
│  Desktop icons   │  open  │  Content         │
│  ┌──┐ ┌──┐ ┌──┐  │  ───►  │  (list OR detail │
│  └──┘ └──┘ └──┘  │  app   │   one at a time) │
│                  │        │                  │
├──────────────────┤        │  Sidebar = drawer│
│ Dock (sm icons)  │        └──────────────────┘
└──────────────────┘         Dock hidden while
                             an app is open
```

Phone windows are forced maximized. The dock disappears while any non-launcher
app is open and returns when it is minimized or closed. Tablet (640–1023px)
behaves the same way but with larger icons and less folded away. The shared
patterns — drawer, `⋯` overflow, icon-only tabs, single-pane, `SelectMenu`,
auto-fit zoom — are listed in [responsive-layout.md §3](responsive-layout.md).

### 1.6 Settings: where the theme controls live

```text
Settings
├── Account        Profile · Password · Security · Sessions · Two-factor
├── Appearance     Theme · Accent color · Wallpapers · Fonts · Icon size
├── Desktop        Desktop icons · Dock settings · Taskbar · Window management
├── Notifications  Enable/disable · Sound · Priority
├── Storage        Used storage · Storage limit · Cleanup
├── Applications   Installed apps · Default applications · App permissions
└── Accessibility  Zoom · Font scaling · Keyboard shortcuts
```

---

## 2. Theme architecture

### 2.1 Layers

```text
Design tokens            design-system/tokens.ts
   colour, type, spacing, radius, elevation, motion, z-index, sizing, focus
        │
Theme catalogue          platform/theme/themes.ts
   14 desktop themes — each a *data* entry: family, accent, wallpaper,
   window chrome classes, optional surface tint
        │
        ├── Shell surfaces     useShellTheme()   dock, top bar, popups, menus
        └── Window chrome      useAppTheme()     one result per open window
        │
User choices             systemStore settings + appPreferences[appId]
   theme · accentColor · wallpaper · fontFamily · icon size · per-app themeChoice
```

A theme is data, not code. Everything that renders chrome reads it from
`platform/theme/themes.ts`; adding a theme means adding one catalogue entry, not
finding every `theme === '…'` test (the file's header comment records why).

### 2.2 Theme families

A theme belongs to one `ThemeFamily` — `light`, `dark` or `terminal`. The family
decides how floating surfaces **behave** (translucency, blur, saturation, inset
highlight, shadow); the theme contributes the **palette** (accent, wallpaper,
optional `surfaceTint`). That is why fourteen themes read as one system.

| Family | Themes |
| ------ | ------ |
| Light | Nova Light, Halo Light, Classic Light, Paper, Ocean |
| Dark | Nova Dark, Halo Dark, Modern Dark, Midnight, Carbon, Ember, OLED Black |
| Terminal | Retro Terminal, Amber Terminal |

The glass treatment shared by every family: a gradient fill that falls off
downward, saturation boosted behind the blur, low fill with high blur, a faint
inset top highlight and a restrained shadow. On dark surfaces a white hairline
defines the edge; on light surfaces the edge is a dark hairline and the shadow
does the separating, because a white border on a pale panel has no contrast.

### 2.3 Two resolvers, deliberately separate

| Surface | Hook | Follows | Why |
| ------- | ---- | ------- | --- |
| Shell chrome (dock, top bar, popups, notification centre, app menu) | `useShellTheme()` | Always the global theme | A dock that disagreed with the desktop behind it is the one inconsistency a user cannot explain. |
| Window and application content | `useAppTheme()` (`appTheme.ts`) | The app's `themeChoice` | Apps may be pinned light or dark. |

Each application stores `themeChoice` under `appPreferences[appId]`:

| Choice | Meaning |
| ------ | ------- |
| `theme` (default) | Follow the global desktop theme, including Ember / Amber Terminal identity. |
| `light` / `dark` | Pinned, whatever the desktop is. |
| `system` | Follow the operating system's `prefers-color-scheme`. |

The pre-existing `theme: 'system'|'light'|'dark'` key is migrated on read
(`'system'` → `'theme'`) and dropped on the next write. Resolution functions:
`resolveAppTheme` (light or dark?), `resolveWindowTheme` (concrete theme id),
`resolveChromeTheme` (collapsed to a family's base id for surfaces that keep
their own class map).

### 2.4 Accent, wallpaper, type, density

* **Accent** — `settings.accentColor`, falling back to the theme's own accent.
  Tailwind cannot build a class from a runtime value, so accent-coloured
  surfaces use inline styles.
* **Wallpaper** — 21 entries in `platform/theme/wallpapers.ts`; `wallpaperTone()`
  returns `light` or `dark`. Desktop icon labels and the top bar colour
  themselves from the **wallpaper's** tone, not the theme.
* **Font** — Poppins (default), Montserrat, Product Sans, Inter, Roboto, set in
  Settings → Appearance → Fonts and applied on the root `<main>`.
* **Icon size** — `sm` 36px, `md` 48px, `lg` 64px; the dock and desktop grid
  follow it, scaled down per device tier.
* **Mono** — JetBrains Mono.

### 2.5 Token scale

| Group | Values |
| ----- | ------ |
| Accent | `#3b82f6` (subtle `#dbeafe`, strong `#1d4ed8`) |
| Semantic | success `#22c55e`, warning `#f59e0b`, danger `#ef4444`, info `#0ea5e9`, each with subtle/strong |
| Neutral | slate scale 0–950 |
| Type size | xs 11px · sm 13px · base 14px · lg 16px · xl 20px · 2xl 24px · 3xl 32px |
| Spacing | 4px base: 0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 |
| Radius | sm 4 · md 8 · lg 12 · xl 16 · 2xl 24 · full · window 12 |
| Elevation | sm · md · lg · window · popover |
| Motion | instant 80ms · fast 140 · normal 220 · slow 360; standard / decelerate / accelerate easings |
| Z-index | desktop 0 · window 100 · active window 200 · dock 300 · top bar 400 · popover 500 · context menu 600 · dialog 700 · toast 800 |
| Focus | 2px accent ring with a 2px offset |

Operation states share one colour map (`stateColor`) so a sync or upload looks
the same in every app: `idle` grey, `pending` amber, `processing` blue,
`success` green, `failed` red, `retrying` dark amber, `offline` slate.

**Known inconsistencies — fix or decide, don't copy:**

1. `tokens.ts` sets the sans font to **Inter**; `index.css` sets the default to
   **Poppins**. The running UI uses Poppins.
2. `tokens.ts` sets `sizing.topBarHeight` to 1.75rem; `TopBar.tsx` renders
   `h-10` (2.5rem).
3. `zIndex` tokens are not used by the shell: `TopBar` uses `z-[9999]`. Treat the
   token table as intent, not as what ships.
4. Tailwind 4's `dark:` variant follows the **operating system**, not the app's
   theme. Surfaces that must match an app's own choice take colours from the
   theme object in scope, never from `dark:` classes.

### 2.6 Adding a theme

1. Add an entry to `THEMES` in `platform/theme/themes.ts` with `id`, `name`,
   `family`, `description`, `accent`, `wallpaper`, `swatch` and `chrome`.
2. Add `surfaceTint` only if the palette needs to colour the panels; do not
   restate blur or shadow.
3. If it needs a new wallpaper, add it to `wallpapers.ts` with its `tone`.
4. Check the dock, a popup, a context menu and one window in the new theme —
   the usual failure is a light menu inside a dark window.
5. Do not branch on a theme id in a component. Branch on `themeFamily`.

---

## 3. UX workflows

### 3.1 First visit to a working desktop

```text
Open any URL
   │
   ├─ Not signed in ──► /login?next=<path>
   │                       ├─ Sign in ──► follow safe `next`, else /
   │                       ├─ Register
   │                       └─ Forgot password ──► email ──► /reset-password
   │
   ├─ /s/:token  ──► public share page (no sign-in)
   │
   └─ Signed in ──► Desktop loads settings synchronously, then opens the window
                    for the URL (/folder/:id → Files, /meeting/:id → Meet)
```

A session that expires mid-use raises a warning notification and returns to
`/login`; `next` brings the user back.

### 3.2 Launching and managing apps

```text
Click a dock icon / desktop icon / launcher tile
   → app opens as a window (one window per app; "New Window" for more)
   → focus raises it (z-index activeWindow)
   → drag title bar to move · drag edges to resize
   → ─ minimise (back to dock)  □ maximise/restore  ✕ close
   → Window menu ▸ Switch To … jumps between open windows
```

On phone/tablet the same actions apply without drag or resize: one full-screen
app, the dock returns on minimise or close.

### 3.3 Working with files

```text
Files ─ browse (grid/list) ─ select (click, Ctrl/Shift, multi) ─ context menu
   ├─ Open ──► the right app (Documents → Word Book, PDF → PDF Viewer, …)
   ├─ Upload / drag-and-drop ──► operation row shows progress
   ├─ Share ──► link / permissions
   ├─ Rename · Move · Delete ──► Trash (recoverable)
   └─ Trash ──► Restore or delete permanently
```

URL tracks the open folder (`/folder/:id`) so reload and links land in place.

### 3.4 Operation states (offline-first feedback)

Every asynchronous action shows the same states, in the same place, next to the
thing it affects — not only as a global toast (`CLAUDE.md` §20, §36).

```text
idle ─► pending ─► processing ─► success
                        │
                        ├─► failed ──► [Retry] ─► retrying ─► processing
                        └─► offline ──► saved locally ─► auto-retry on reconnect
```

Messages answer five questions: what happened, why, whether the work is saved,
whether it will retry, and what the user can do.

```text
Could not upload "project-report.pdf"

You are offline. Your change is saved locally and will be
synchronised when you reconnect.                      [Retry]
```

The shell reports network changes itself: losing the connection switches the
system to offline mode with an error notification; regaining it notifies success.
`SyncStatusIndicator` is the persistent sync badge.

### 3.5 Notifications

```text
Event (message, share, system) ─► realtime connection (shell-level, works with
Messenger closed) ─► toast (SystemToastNotifier) ─► kept in the notification
panel (dock 🔔) ─► click opens the source app
```

### 3.6 Changing the look

```text
Settings ▸ Appearance
   Theme ───────► pick a preset: sets theme + accent + wallpaper together
   Accent color ─► override the accent only
   Wallpapers ──► override the wallpaper only
   Fonts / Icon size
   (per app) View/App menu ▸ Theme ▸ Theme · Light · Dark · System
```

Global choices apply to the shell and to every app left on `Theme`. An app
pinned to Light or Dark ignores the global theme but keeps the shell's.

### 3.7 Keyboard and accessibility

| Action | Shortcut |
| ------ | -------- |
| New window | Ctrl+N |
| Minimise | Ctrl+M |
| Close window | Ctrl+W |
| Keyboard shortcuts | Ctrl+/ |
| Help | F1 |
| Cut / Copy / Paste | Ctrl+X / C / V |

Required of every new surface (`CLAUDE.md` §43): a visible focus ring
(`tokens.focus`), keyboard reachability of every control, `aria-label` and
`title` on icon-only buttons, `role="listbox"`/`"option"` on custom selects,
reduced-motion respect, and every hover-only control reachable by touch
(`useSupportsHover()`).

### 3.8 Definition of done for a screen

Happy path · loading state · empty state · validation · permission and sign-in
handling · network failure · offline behaviour · retry · error UI placed at the
operation · keyboard and screen-reader behaviour · phone/tablet layout ·
tests. If a feature needs a connection, the UI must say so (`CLAUDE.md` §49).

---

## 4. Rules for changing the UI

1. Take colours from the shell or app theme object, never from hard-coded
   hex values and never from `dark:` classes.
2. Branch on `themeFamily`, not on a theme id.
3. Floating shell surfaces use the `ThemeSurfaces` vocabulary (`panel`, `card`,
   `hover`, `text`, …) — do not write per-call-site translucent backgrounds.
4. Choose the responsive signal first (viewport for device class, container
   width for window width) — see [responsive-layout.md §2](responsive-layout.md).
5. Click-outside listeners run in the capture phase; overlays need a positioned
   parent.
6. New apps reuse `design-system/components` before adding their own primitives.
7. When a change touches theme behaviour, update this document in the same change.

## 5. Not covered here

* No design file (Figma or similar) exists in the repository; the wireframes
  above are derived from the code and should be replaced by the design source if
  one is created.
* The theme picker's visual behaviour has not been verified in a browser for this
  document — it is `REVIEWED` from source only.
