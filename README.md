# Military Duels

A Roblox 1v1 and 2v2 military duel shooter, designed by **Noelle Moore** and dedicated to **Joanna Moore** and **Eddie Moore**.
The full design is in `research/brief.md`. Code lives in `src/` and syncs into Roblox Studio with Rojo. Toolchain and daily loop are the same as noma-roblox: `rokit install`, `rojo serve`, and `./scripts/check.sh` prints `CHECK OK`.

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
| Claude (phase 1) | `grok -m grok-4.7 --permission-mode plan` (read-only) | `codex exec -` |
| Grok 4.7 (`omp --model grok-4.7`) | `claude -p` | `codex exec -` |

Costs grow with the size of `src/`, because every run sends the whole source to the judge 3 times.
