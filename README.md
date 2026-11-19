# Military Duels

A Roblox 1v1 and 2v2 military duel shooter, designed by **Noelle Moore** and dedicated to **Joanna Moore** and **Eddie Moore**.
The full design is in `research/brief.md`. Code lives in `src/` and syncs into Roblox Studio with Rojo. Toolchain and daily loop are the same as noma-roblox: `rokit install`, `rojo serve`, and `./scripts/check.sh` prints `CHECK OK`.

## Play it (phase 1)

1. `rojo build default.project.json -o MilitaryDuels.rbxl`, then open the file in Roblox Studio.
2. Press **Play**. Playing alone, you duel the Recruit Bot; with 2 players in a Studio test server, it's player vs player and any extra players watch from the glass gallery.
3. Controls: **click** to fire, **right-click** to aim (tighter spread, slower walk), **R** to reload. The ladders on the central tower and the ramps inside the two offices lead up high.

Rules: first to 5 round wins. Each round lasts 2:00, and a timeout is a draw with no point. Teams swap sides every round. You get a 3-second spawn shield, which drops the moment you fire. Damage multipliers: head ×3, body ×1, legs ×0.5.

**Anti-cheat:** the place runs with Roblox **Server Authority** (`Workspace.AuthorityMode = Server` in `default.project.json`). The server simulates all movement, so speed, fly and teleport hacks don't move your character. The server script refuses to start without it. Every shot is validated and cast on the server:
- ammo and fire rate
- shot origin
- aim direction vs body facing and reported look
- walls
- lag-compensated hitboxes

Rejected actions add to the `CheatFlags` player attribute; phase 6 adds the penalties.

**Phase 1 status:**
- Built, and verified in Studio Play: full matches against the bot, scoring, side swaps, reloads, rematches, and forged shots rejected. Timeout draws are implemented but haven't been seen in a test yet.
- The judge scores 59–62. Remaining judge concerns are mostly limits of the platform; for example, camera pitch can't be verified by the server.
- Noelle's playtest is the real gate before phase 2.

## Build plan: 6 phases, not one shot

Each phase is a playable game on its own. The autoresearch loop builds one phase at a time against a locked scope, and Noelle playtests it before the next phase is unlocked.

| Phase | Scope | Line cap |
|---|---|---|
| 1 | Core duel: Shooting Range, 1v1 vs bot, assault rifle, hitboxes, first-to-5, timer and draws, server-side hit validation | 2500 |
| 2 | Arsenal: full loadout, SMG, shotgun, sidearm, knife, smoke, frag, med kit, Sudden Death sniper/knife, 2v2 with bots | 4000 |
| 3 | Desert Outpost and Urban Training Town, plus the 4 drop-in vehicles | 5500 |
| 4 | Bullet cam, anime finisher, handshake draws, Camp Moore lobby, statue, dedication, HUD color picker | 7000 |
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
