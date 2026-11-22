# Military Duels

A Roblox 1v1 and 2v2 military duel shooter, designed by **Noelle Moore** and dedicated to **Joanna Moore** and **Eddie Moore**.
The full design is in `research/brief.md`. Code lives in `src/` and syncs into Roblox Studio with Rojo. Toolchain and daily loop are the same as noma-roblox: `rokit install`, `rojo serve`, and `./scripts/check.sh` prints `CHECK OK`.

**Port 34873.** This game's `rojo serve` uses port 34873 (`servePort` in `default.project.json`); Stink-a-Dad in `~/orca/noma-roblox` uses 34872. In Studio's Rojo panel, set the port to **34873** before clicking Connect, or the window will receive Stink-a-Dad's code instead.

## Play it

1. `rojo build default.project.json -o MilitaryDuels.rbxl`, then open the file in Roblox Studio and press **Play**.
2. A loading screen shows the dedication ("Military Duels — dedicated to Joanna & Eddie Moore"), then you spawn in **Camp More Maniar**, the lobby: the statue of Joanna and Eddie Moore, the shop, the armory, the coin leaderboard and a free **practice range** (walk up to a rack and press **E** to try any weapon on the target dummies; walk off the range or press LEAVE RANGE to stop). On your first join you pick your HUD colors; change them any time with **SETTINGS**.
3. On the bottom bar:
   - pick a map: **Shooting Range**, **Desert Outpost** or **Urban Training Town**;
   - pick **1v1** or **2v2**;
   - press **PLAY**.

   Everyone who queues for the same map plays together; the first player in the queue picks the mode, and bots fill empty slots. Bots wear the avatars and names of the players' Roblox friends. All three maps can run matches at the same time.
4. **Each round starts with a drop-in** (10 s), picked at random: a helicopter fast-rope, an army truck, a parachute jump or an armored car. Pick your loadout during the ride: a primary (Assault Rifle, SMG, Shotgun or Sniper), a melee and a gadget (Frag, Smoke or Med Kit). Everyone also carries a Pistol. You can't act until you land; the spawn shield starts at landing.
5. Controls:
   - **click** fires or swings; **right-click** aims (the sniper scopes in)
   - **R** reloads; **1 / 2 / 3** or the mouse wheel switches weapons; **G** uses the gadget
   - **Shift** sprints; **C** crouches, or slides while sprinting; **Space** twice double-jumps

Rules:
- First to 5 round wins. Each round lasts 2:00; a timeout is a draw with no point. Teams swap sides every round.
- A 3-second spawn shield drops the moment you fire or throw.
- Damage multipliers: head ×3, body ×1, legs ×0.5. Melee always does 55.
- **Sudden Death at 4–4:** each team gets one sniper and one melee fighter.
- **Cutscenes** (the next round waits until everyone has seen them):
  - a round won with a headshot plays the **bullet cam** (slow-motion bullet, "HEADSHOT — CRITICAL HIT");
  - every round win plays the **anime finisher** (freeze frame, zoom, speed lines, the winner's name card, stylized ink slashes, winner standing over the defeated player);
  - a draw plays the **handshake**: one fighter from each team walks to the middle and shakes hands.
- The winning team gets a **celebration** in the sky above the arena, then everyone returns to the lobby.

**Coins and the shop** (no real money, ever):
- Win: 120 coins if the match-winning elimination was a headshot, otherwise 80. Losers get 10 per round they won. New players get 350 once ("beginner's luck").
- **Shop › Skins** recolor weapons; equip them per weapon in **Inventory**.
- **Shop › Weapons:** **Double Trouble** (twin dark katanas, melee) and **A Mother's Wrath** (dark-blue sniper with blue shots and lightning). They have exactly the stats of the Combat Knife and the Sniper; pick them on the loadout screen.
- Developers listed in `Config.Developers` own everything for free.
- Coins save with DataStore on published places; in Studio without API access they last for the session.

**Anti-cheat:** the place runs with Roblox **Server Authority** (`Workspace.AuthorityMode = Server`), so the server simulates all movement and the server script refuses to start without it. Every shot is validated and cast on the server (ammo, fire rate, origin, aim vs facing and reported look, walls, lag-compensated hitboxes). Rejected actions add to the `CheatFlags` player attribute.

## Checking and testing

Every change goes through two gates before it merges:

1. **Code checks:** `./scripts/check.sh` must print `CHECK OK` (formatting, selene lint, strict Luau types, place build). GitHub Actions runs it on every pull request (`.github/workflows/check.yml`), plus format and lint of the game test.
2. **Game test in Studio:** `./scripts/playtest.sh` (macOS; needs Roblox Studio and Accessibility permission for the terminal). It builds `tests/playtest`, which is the real game plus two test scripts, opens one Studio window, presses Play and closes the window afterwards. It checks:
   - the lobby spawn, the three arenas, the lobby bar, coins and shop ownership;
   - queueing, the match going live, the player's weapon;
   - bots moving, shooting and not dying on their own, and the player's shots hurting the bot;
   - the match ending, the celebration, the return to the lobby and the arena resetting.

   It prints a `PLAYTEST PASS`/`FAIL` line per check and ends with `PLAYTEST OK`, or exits non-zero on any failure, script error or timeout. Gameplay is untouched until the match-end checks, which finish the match through the normal damage path.

Noelle's playtest is still the real gate for each phase.

## Build plan: 6 phases, not one shot

Each phase is a playable game on its own. The autoresearch loop builds one phase at a time against a locked scope, and Noelle playtests it before the next phase is unlocked.

| Phase | Scope | Line cap |
|---|---|---|
| 1 | Core duel: Shooting Range, 1v1 vs bot, assault rifle, hitboxes, first-to-5, timer and draws, server-side hit validation | 2500 |
| 2 | Arsenal: full loadout, SMG, shotgun, sidearm, knife, smoke, frag, med kit, Sudden Death sniper/knife, 2v2 with bots | 4000 |
| 3 | Desert Outpost and Urban Training Town, plus the 4 drop-in vehicles | 5500 |
| 4 | Bullet cam, anime finisher, handshake draws, Camp More Maniar lobby, statue, dedication, HUD color picker | 7000 |
| 5 | Saved coins, XP and levels, payouts, beginnersluck, shop, starter pick, Double Trouble, Eddie's Honor, A Mother's Wrath, Ranked | 8500 |
| 6 | Cheat flag thresholds, Bot Bootcamp, report replays, matchmaking queues, Remote audit | 10000 |

Server authority (hits, ammo, movement) is built into phase 1 because everything later depends on it. Phase 6 only adds the penalties on top.

To start or advance a phase, follow `research/SETUP.md`.

## Model config

The judge must be a different model family than the builder, so no model grades its own work. Set `research/eval/judge.env` before running `research/lock.sh` for each phase.

| Builder | Judge (`JUDGE_CMD`) | Holdout, every 5th run |
|---|---|---|
| Claude (phase 1) | `codex exec -s read-only -` | blank |
| Grok 4.7 (`omp --model grok-4.7`) | `codex exec -s read-only -` or `claude -p` | the other one |

Grok works as the builder but not as the judge: `grok -p` gave no answer to the ~86 KB scoring prompt within 5 minutes.

Costs grow with the size of `src/`, because every run sends the whole source to the judge 3 times.
