# Smoking Gnomes Inc.

The guild's gnome-harvesting Production Report: a leaderboard for gnomes killed in world PvP, plus Corporate Spies (bounties) reported by officers.

## Install (guild members)
**With WowUp (recommended, updates itself):**
1. Install [WowUp](https://wowup.io) (version 2.24.0 or later supports WoW Forever) and make sure it has found your Forever install.
2. Go to **Get Addons → Install from URL** and paste this repository's GitHub link.
3. That's it. WowUp updates the addon whenever a new version is released.

**By hand:** download the latest `SmokingGnomes-vX.Y.Z-forever.zip` from this repository's **Releases** page and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`.

Log in, then type `/gnomes` or click the addon button next to the minimap. If someone in the guild has a newer version, the addon tells you once per session.

## Job titles
Your title is based on lifetime gnomes. It shows on the Production Report, and in your tooltip to every guildmate running the addon.

| Lifetime gnomes | Title |
|---|---|
| 0 | Unpaid Intern |
| 1 | Lab Assistant |
| 10 | Field Harvester |
| 25 | Pharmacist |
| 50 | Senior Chemist |
| 100 | Head of R&D |
| 250 | Chief Medical Officer |
| Guild master | CEO |

Last week's top harvester is **Employee of the Week** for the following week. They get a star on the board and a line in their tooltip.

## Hall of Fame and the weekly bonus
- After each weekly reset, the addon of the first guild master or officer online names last week's top scorer **Employee of the Week**, posts it in guild chat, and adds the week to the **Hall of Fame**. Click the Employee of the Week line at the top of the window (or type `/gnomes hall`) to see every past winner.
- **Bonus:** officers set the weekly gold bonus with `/gnomes prize 50` (0 for none). It applies to the next winner, and to the latest one still unpaid. Pay it by hand, then type `/gnomes paid`: the Hall of Fame shows it as paid and guild chat gets a thank-you.
- The Hall of Fame starts with the week ending 2 December 2026. Only the guild master and officers (the top two ranks) can name winners or mark bonuses paid; everyone's addon checks that against the guild roster.

## Guildmates' kills
- Off by default. Switch on **Guildmates' kills** in Settings to get a popup when a guildmate running the addon harvests a gnome ("Lih Zaddi smoked Fizzwick, in Felwood"). Nothing is posted in guild chat.

## Corporate Spies (bounties)
- **Who can post:** the guild master and the rank directly below (guild rank index 0 and 1). To change this, edit `OFFICER_RANK` at the top of `Bounty.lua`.
- **How to report one:** use the **Spies** tab: type a name (or leave it empty to use your current target), add a reward, then click **Report**. Or type `/gnomes spy Fizzwick 50 gold`.
- **Who it can target:** any player, not just gnomes. Use `Name-Realm` for players from another realm.
- **Claiming:** the first guildmate to land the killing blow (or whose pet does) in the open world claims it automatically. If two claims arrive, the earlier kill wins. The addon checks that the claimed kill really was the named player whenever it can.
- **Rewards:** the officer pays these by hand. The addon only records who earned what.
- **The list:** withdrawn reports disappear straight away, expired ones after a day, and eliminated spies stay on the tab as trophies until the weekly reset.
- **Expiry:** reports expire after 7 days. The officer who reported a spy can withdraw it with shift + right-click on the Spies tab, or `/gnomes spy cancel Fizzwick`.
- **What everyone sees:** a popup when a spy is reported or eliminated, a red "Corporate spy" line when hovering them in the world, and "Spies eliminated" in each player's tooltip on the board.
- Notices and claims are signed and relayed the same way as kill counts, so people who were offline still get them.

## Repeat customers
- Every gnome kill is shared with the guild as a small signed record.
- Hovering an Alliance player shows "Smoked by the company: 3×", plus who has killed them most often. Regulars get a label: Repeat customer (3), Loyal patient (10), Lifetime subscriber (25).
- The **Lab Log** shows the same count next to each of your kills.
- When you log in, guildmates send only the kills made since you were last online.
- Counting starts with version 0.8.0. Earlier kills aren't included.

## Guild crest
The window and popups use the logo file. `/gnomes crest` shows what the game itself gives for the guild's tabard emblem, large, and prints its file number and colours, which is what the logo is rebuilt from. `/gnomes crest on` tries drawing that live crest in the window instead, and `/gnomes crest off` switches back.

## Gank mode
Turn it on with `/gnomes gank`, shift-click on the minimap button, the Settings view, or a key (Key Bindings → Smoking Gnomes Inc.).
- Enemy gnomes you see (nameplates, mouseover or target) get a **"Gnome spotted"** popup with a short ping, plus how often the company has smoked them. Corporate spies of any race get a red **"Corporate spy spotted"**.
- A small panel lists everyone spotted in the last 3 minutes. **Click a name to target that player.** The **"Target the last spotted gnome"** key binding does the same.
- The panel also lists, quietly, gnomes that **your party or raid has targeted** ("Molly's target") and gnomes that **guildmates in your zone spotted** ("Molly · 2m ago"). Clicking only reaches about 100 yards, so these may be out of range. Hover a row for details.
- Your own gnomes always come first. At most 3 guildmates' spots are listed; the rest are counted in the header ("+5 guild"). Switch guild spots off in Settings if you only want your own.
- Drag the corner of the panel to resize it (outside combat): wider for long names, taller for up to 12 names.
- Each player is called out at most once every 3 minutes. Battlegrounds and arenas are ignored.
- Targeting always needs your click or key press. Addons can't choose a target by themselves, the same as Next!. The list can't change during combat, so it updates when the fight ends.

## Settings
Click the cog in the window header, or type `/gnomes settings`: window size (70–150%), background opacity, gank mode, callout sound, popups and the minimap button.

## Rules
- **Gnome:** your killing blow (or your pet's) on a player whose race is Gnome.
- **Assist:** a gnome killed by someone in your party or raid, or a gnome that dies near you while you're awarded honor for it (you helped, even if the killer isn't grouped with you). Assists score no points and are used only to break ties.
- **PvP tab:** every Alliance player you (or your pet) kill in the open world, gnome or not, this week and lifetime. It's for general PvP stats; points, titles and Employee of the Week still come from gnomes only. Counting starts from version 0.17; earlier kills there are only your gnomes.
- **World PvP only:** kills in battlegrounds and arenas don't count.
- **Weekly points:** the Weekly board ranks by points. Each gnome scores by its level against yours, so a fair fight is worth the same at level 20 as at 60:

  | The gnome is… | Points |
  |---|---|
  | your level or higher | 1.25 |
  | 1–5 levels below you | 1 |
  | 6–10 levels below | 0.5 |
  | 11 or more below | 0.25 |

  Ties go to more gnomes, then more assists. Lifetime totals and job titles still count gnomes. Kills from before points arrived count 1 point each. `/gnomes points` prints this table in game.
- **Weekly reset:** at the server's weekly reset. Last week's top scorer is Employee of the Week, shown in the window header.

## How sync works
- Numbers travel over the hidden guild addon channel. Nothing appears in guild chat.
- After a kill, your addon sends your numbers to everyone online.
- When someone logs in, the players online pass along everything they know, including kills made while that person was offline. Hover a name to see whether you heard from them directly or "through guildmates".
- If you reinstall or move to a new PC, the guild sends your numbers back to you within about a minute of logging in.

## Anti-tamper
- Each player's numbers are stored and sent as one signed record. Editing the saved file, or sending numbers with a `/run` script, breaks the signature, and every other player throws that update away.
- If your own saved file has been edited, your addon resets your numbers and takes your real ones back from the guild.
- Other players also check that each update makes sense: numbers can't go down, and they can only go up at roughly a kill every 30 seconds since the last update, with a cap of 100 per update. Anything else is rejected and shows up in that player's tooltip.
- Hovering a name shows the last gnome they killed, so made-up kills are easy to question.
- Because the addon code is readable, someone determined could still work around this. It stops casual cheating; it can't stop all cheating.

## Commands
| Command | Effect |
|---|---|
| `/gnomes` | Open or close the leaderboard |
| `/gnomes stats` | Print your numbers |
| `/gnomes status` | Check it's working: kills seen this session, guildmates with the addon heard from, version |
| `/gnomes board` | Print this week's top 10 in chat |
| `/gnomes points` | How weekly points work |
| `/gnomes standings` | Show the login message again: this week's top 3, your place, and the Employee of the Week (it appears by itself about 30 seconds after you log in; switch it off in Settings) |
| `/gnomes hall` | Open the Hall of Fame: every Employee of the Week and their bonus |
| `/gnomes prize <gold>` | Officers: set the weekly bonus (0 for none) |
| `/gnomes paid` | Officers: mark the latest bonus as paid |
| `/gnomes spies` | List suspected corporate spies in chat |
| `/gnomes spy <name> [reward]` | Officers: report a corporate spy (leave the name out to use your target) |
| `/gnomes spy cancel <name>` | Officers: withdraw your report |
| `/gnomes toast` | Turn popups on or off |
| `/gnomes gank` | Gank mode on or off |
| `/gnomes settings` | Window size, background opacity and switches |
| `/gnomes minimap` | Hide or show the minimap button (left-click opens the window, right-click shows commands, drag to move) |
| `/gnomes help` | List all commands in chat and open the Commands view. The **?** button in the window does the same |
| `/gnomes crest` | Show the guild crest large with its exact colours (for screenshots) |
| `/gnomes crest on` / `off` | Try the live guild crest instead of the logo file, or switch back |
| `/gnomes killlog` | The last 20 kill signals this session: deaths near you, honor awards, party kills, and what was credited |
| `/gnomes tipdebug` | Print what the tooltip hook sees for the next 5 players you hover |
| `/gnomes version` | Show your version, and whether a newer one is out |

## Releasing a new version (maintainers)
1. Commit the changes.
2. Tag the commit and push the tag: `git tag v0.9.1` then `git push origin main v0.9.1`.
3. GitHub Actions builds `SmokingGnomes-v0.9.1.zip`, writes the version into the `.toc`, and publishes the release. WowUp users get it automatically.

Keep `## Version: @project-version@` in the `.toc`; the release build fills it in.
| `/gnomes sync` | Ask the guild for fresh numbers |
| `/gnomes test` | Show a fake kill popup. Your numbers don't change. |
| `/gnomes test promo` | Show a fake promotion popup |
| `/gnomes check` | Self-test the anti-tamper signing |

## Test plan (before sharing)
1. `/console scriptErrors 1`, then `/reload`. You should see no Lua errors.
2. `/gnomes check`. You should see "Check passed".
3. `/gnomes test`. You should see a "Gnome smoked!" popup with the guild logo, and "Test Gnome (test)" under **My kills**.
4. With two guild members online who both have the addon: each should appear on the other's board within about 20 seconds of logging in.
5. Relay: player A kills a gnome while player B is online and player C is offline. When C logs in, A's kill should appear on C's board even if A has logged off.
6. Kill a real gnome in the open world. Check the popup, the board, and that a guildmate sees your new count.
7. Corporate spies: an officer reports one. A guildmate online should get the popup and see it on the **Spies** tab. Kill the spy and check that both of you see it as eliminated.
