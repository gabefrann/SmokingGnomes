# UI redesign: "memo in a game frame"

Status: **in progress on branch `ui/memo-redesign`.** This file is the handoff: it records every decision so the work can continue on another device or in another session. The visual reference is the design canvas "Smoking Gnomes UI Looks" (claude.ai artifact, private to the owner; the dark-mode row and the "Tabs C" board are the approved designs).

## What changes, in one paragraph
The main window becomes a game-style frame (dark wood, gold trim) with the guild crest in a round portrait slot over the top-left corner, and a "page" inside it in one of two themes: **dark** (default) or **light paper**. Tabs hang **below** the window like the character sheet's. Every page lines up on one 16 px margin. Popups stay **exactly as they are today**. The gank panel gets the same frame and a SPY tag.

## Frame (both themes)
| Part | Value |
|---|---|
| Window | 340 × 520 at 100 % scale, movable, Escape closes |
| Frame | wood `#1A130B`, 3 px edge `#4A3520`, 1 px gold trim `#B8913F` inset 4 px |
| Crest | 52 px gold ring (`#C9A64A`) over the top-left corner, offset −12/+12, logo 42 px inside |
| Title | "Smoking Gnomes Inc.", 15 px, gold `#FFD100`, outlined, starts right of the crest |
| Header buttons (right) | Payroll (gold coin), Settings (cog), Close (red square). 22 px, active one gets a gold edge |
| Page | inset 6 px inside the frame, below a 36 px title bar |
| Page margin | 16 px. Logo-free content (headings, bands, tables, footers) all start on this margin |

### Tabs (below the window)
Report · PvP · Spies · Lab Log. Payroll is **not** a tab (coin icon). (Weekly and Lifetime were merged into Report on 28 Nov 2026; see below.)
- Normal: dark face `#1D1610`, bronze edge `#5A4620`, no top edge, rounded bottom, text `#C9B48A`.
- Hover: edge `#B8913F`, text `#FFF0C0`.
- Active: taller (+4 px) and larger text (13 vs 12), gold edge `#D9B04A`, gold text (dark theme) or parchment face with ink text (light theme), soft glow.
- On Payroll / Settings / Commands no tab is active; those pages have their own Done / Back button.

### Themes
| Token | Dark | Light |
|---|---|---|
| paper | `#1F1A14` | `#E4CFA1` |
| ink | `#EADFC8` | `#2A1F14` |
| muted | `#A89878` | `#5E4A33` |
| accent (green) | `#6FBF86` | `#1F5A32` |
| red | `#E0705F` | `#9B2C1F` |
| gold | `#FFD100` | `#7A5A10` |
| your row | gold 10 % | `#FFD633` 50 % (highlighter) |
| medals 1/2/3 | `#E0B341` `#B8BCC2` `#C58A55` | `#A07A1C` `#6F7378` `#8A5A2B` |
| names | class colours | ink + a small class-colour dot (yellow/white can't be read on paper) |

Theme is a Settings row ("Theme: Dark / Light"), saved in `SmokingGnomesDB.settings.theme`.

### Fonts
Built-in only for now: Friz Quadrata (`STANDARD_TEXT_FONT`) for text, Arial Narrow (`Fonts\ARIALN.TTF`) for numbers and small print. The mock-ups use Special Elite (headings) and Courier Prime (numbers); both are OFL and could be shipped in `Media/` later. **No name is ever cut off**: long names shrink a size or two first.

## Pages
All pages: heading (15 px, uppercase) at the top-left, optional subtitle under it, optional action on the right, content, footer at the bottom.

**Report** — "PRODUCTION REPORT", subtitle "Kill gnomes in world PvP to climb and get promoted."
- A **This week | All time** switch under the subtitle. Both periods use identical single-line rows; only the numbers change. The tab reopens the period you last used.
- This week columns: NO. · EMPLOYEE · POINTS · GNOMES. All time: NO. · EMPLOYEE · HONORABLE · GNOMES. Job titles are in the row tooltip.
- Employee of the Week band in both periods. Ranks 1–3 in gold/silver/bronze rings; the line under #3 is dashed (no extra gap).
- Your row highlighted (fading ends); on This week it says "x.xx to #N" for the place above you.
- Progress strip: "You · Title" left, "N to Next title · +Xs a week" right (drops words to fit). No tooltip on it.
- Footer: This week "Resets in …" · "Company this week: N gnomes"; All time "Your rank #N of M" · "Company all time: N gnomes".

**PvP** — "FIELD REPORT", subtitle "Every Alliance player killed in the open world."
- Columns: NO. · EMPLOYEE · WEEK · LIFETIME.
- Three stat boxes at the bottom (owner prefers this version): YOU THIS WEEK (n, rank) · OF THEM GNOMES (n, "count for points") · YOU LIFETIME (n Alliance).
- Note line "Points, titles and salaries still count gnomes only." Footer: reset · company this week.

**Spies** — "CORPORATE SPIES" (red), right: "N at large", subtitle "Kill on sight in the open world. First kill collects."
- "Most wanted" card: the open report with the highest reward (number parsed from the reward text): portrait, name, reporter, time left, reward.
- "Other cases": portrait, name, one detail line, reward, a fixed-width status box (AT LARGE / ELIMINATED / EXPIRED). Withdrawn reports never show (the addon drops them).
- Portraits: the class icon when the spy was seen this session (gank data), otherwise the generic portrait.
- Officer form at the bottom ("Name, or blank for target" · Reward · REPORT), footer "You've eliminated N".

**Lab Log** — "LAB LOG", subtitle "Your last 10 harvests."
- Columns: WHEN · GNOME · POINTS. Detail line: zone · "smoked N×" · regular label · assist / grey.
- "Your career" block (only here): current title ─ bar ─ next title, then "50s a week · 12 more to go · 75s a week +25s".

**Payroll** (coin) — "PAYROLL" + status box (PAID / UNPAID / PREVIEW) + DONE.
- Subtitle "Week ending … No work, no pay." (budget-cap note when cut).
- Two-line rows: name + title · GNOMES · SALARY. Progress strip "Your pay · X" / "N to Next · +Ys a week". Footer "N paid" · "Total X".

**Settings** (cog) — "SETTINGS" + DONE, subtitle "Saved for all your characters."
- Rows: Theme, Window size, Background opacity, Gank mode, Guild spots, Callout sound, Popups, Guildmates' kills, Login standings, Minimap button.
- Footer: "SLASH COMMANDS →" button and the version.

**Commands** — "SLASH COMMANDS" + "← SETTINGS". The "?" header button is gone; the minimap right-click still opens this page.

## Long lists
Weekly, Lifetime, PvP, Payroll and Spies' cases show a page of rows and **scroll with the mouse wheel**; a small "1–10 of 34" appears in the column header when there's more. Your own row stays pinned at the bottom when it's off the visible page (Weekly/Lifetime/PvP).

## Popups
Unchanged from the current addon (logo + outlined text, no background). Full names.

## Gank panel
Same wood frame and gold trim, title "SIGHTING LOG" in gold. Names in class colours (spies too); spies get a red "SPY" tag in the status column. Level stays in the status column.

## Decisions after in-game testing (27–28 Nov 2026)
- Window 308 px wide; height fits the page with a 360 px minimum; opens at 105 % (corner grip to resize; top-left stays put).
- Window on HIGH strata and toplevel; popups on DIALOG.
- Light theme removed. Gold stays. Logo/crest unchanged.
- **No custom fonts:** WoW Forever refuses addon font files (SetFont returns false, even for Details' and Plater's fonts). Morpheus was tried for headings and rejected. Headings are Friz Quadrata 18; `/gnomes fonts` previews every built-in font the client accepts.
- Page margin 18 px; rows 24 / 34 (two-line) / 38 (spy cases); numbers 12, rank and time 11.
- Tabs: rounded bottoms (tooltip border, top clipped), 2 px gaps, centred.
- The ladder tooltip shows only on the Lab Log's "Your career" box.
- Company feed tried and removed (too busy). One-time welcome page (`/gnomes welcome`).
- Spies: × to withdraw your own open report.

## Implementation status
- [x] Design approved on the canvas
- [x] `UI.lua` window, tabs, themes, all pages, mouse-wheel scrolling (window section rewritten; popups, tooltips, minimap button unchanged)
- [x] `Gank.lua` restyle + SPY tag + `Gank.Seen(name)` (class for spy portraits)
- [x] README updated (no "?" button, theme setting, scrolling)
- [ ] **Tested in game** — written without a Lua interpreter; only block/bracket balance was checked. Test: `/console scriptErrors 1`, `/reload`, every tab, Payroll/Settings/Commands and their Done/Back, both themes, 70 % and 150 % scale, mouse wheel on a long list, officer form, gank mode with a spy.

### Where things are in `UI.lua`
- Constants and theme palettes: top of the "Window" section (`THEMES`, `W`, `H`, `PAD`).
- Builders: `buildFrame` (frame, crest, header buttons, tabs), `buildHead`, `buildParts`, `buildForm`, `buildSettings`, `buildHelp`.
- Pages: `refreshBoard` (Weekly/Lifetime/PvP via `BOARDS`), `refreshRecalls`, `refreshMine`, `refreshPayroll`; Settings and Commands in `UI.Refresh`.
- Theme: `UI.ApplyTheme()` repaints everything registered through `themed(...)`.
