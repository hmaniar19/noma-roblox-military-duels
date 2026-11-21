# Military Duels

A Roblox 1v1 and 2v2 military duel shooter, designed by **Noelle Moore** and dedicated to **Joanna Moore** and **Eddie Moore**.
The full design is in `research/brief.md`. Code lives in `src/` and syncs into Roblox Studio with Rojo. Toolchain and daily loop are the same as noma-roblox: `rokit install`, `rojo serve`, and `./scripts/check.sh` prints `CHECK OK`.

**Port 34873.** This game's `rojo serve` uses port 34873 (`servePort` in `default.project.json`); Stink-a-Dad in `~/orca/noma-roblox` uses 34872. In Studio's Rojo panel, set the port to **34873** before clicking Connect, or the window will receive Stink-a-Dad's code instead.

## Play it (phases 1–2)

1. `rojo build default.project.json -o MilitaryDuels.rbxl`, then open the file in Roblox Studio.
2. Press **Play**.
   - **Lobby (6 s):** pick **1 v 1** or **2 v 2** for the next match. Bots fill every empty slot, so you can play 2v2 alone with a bot teammate. Extra players watch from the glass gallery.
   - **Before each round (8 s):** pick a **primary** (Assault Rifle, SMG or Shotgun) and a **gadget** (Frag, Smoke or Med Kit). Everyone also carries a **Pistol** and a **Combat Knife**.
3. Controls:
   - **click** to fire or stab
   - **right-click** to aim (tighter spread, slower walk; the sniper scopes in)
   - **R** to reload
   - **1 / 2 / 3** or the **mouse wheel** to switch weapons
   - **G** (or **4**) to throw or use your gadget

   The ladders on the central tower and the ramps inside the two offices lead up high.

Rules:
- First to 5 round wins. Each round lasts 2:00, and a timeout is a draw with no point.
- Teams swap sides every round.
- You get a 3-second spawn shield, which drops the moment you fire or throw.
- Damage multipliers: head ×3, body ×1, legs ×0.5. The knife always does 55.
- **Sudden Death at 4–4:** each team gets one **Sniper** and one **Combat Knife** and nothing else. Pick your role on the pre-round screen; if both teammates want the same role, the first pick wins.

Gadgets:
- **Frag:** explodes after 2.2 s. Damage falls off with distance, and walls block the blast.
- **Smoke:** a 12-second cloud that hides players, including from bots.
- **Med Kit:** +50 HP over 3 s. You can't shoot while it runs, and taking damage cancels it.

**Anti-cheat:** the place runs with Roblox **Server Authority** (`Workspace.AuthorityMode = Server` in `default.project.json`). The server simulates all movement, so speed, fly and teleport hacks don't move your character. The server script refuses to start without it. Every shot is validated and cast on the server:
- ammo and fire rate
- shot origin
- aim direction vs body facing and reported look
- walls
- lag-compensated hitboxes

Rejected actions add to the `CheatFlags` player attribute; phase 6 adds the penalties.

**Status:**
- Phase 1 is verified in Studio Play: full matches against the bot, scoring, side swaps, reloads, rematches, and forged shots rejected. Timeout draws are implemented but haven't been seen in a test yet.
- Phase 2 is verified in Studio Play:
  - 2v2 with bots filling three slots, and team elimination
  - the lobby mode pick, and loadout picks applied each round
  - shotgun, SMG, pistol and AR hits
  - slot switching, smoke and the med kit
  - Sudden Death at 4–4 (the sniper role), then match end, lobby and rematch
- The judge scores phase 2 at 54–61. Remaining judge concerns are mostly limits of the platform; for example, camera pitch can't be verified by the server.
- Noelle's playtest is the real gate for each phase.

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
