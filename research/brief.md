# Owner brief: Military Duels

Designed by **Noelle Moore** (age 12) over a 10-round brainstorm, 2026-11-18.
Dedicated to **Joanna Moore** and **Eddie Moore**.

Present-day military FPS duels on Roblox: 1v1 and 2v2, realistic look, intense but honorable.

## 1. Match rules
1. Modes: **1v1** and **2v2**. **First to 5 round wins.**
2. Each round has a **2:00 timer**. If time runs out the round is a **draw**: both teams walk to the middle and do a **handshake cutscene**. No point is awarded.
3. **4–4 = Sudden Death.** Normal loadouts are replaced:
   - 2v2: one player per team gets a **sniper**, the teammate gets a **combat knife**. The team chooses who gets which during the drop-in.
   - 1v1: each player picks sniper or knife.
   - The sniper exists **only** in Sudden Death.
4. Teams **swap sides every round**.
5. **3-second spawn shield** after landing. It drops early if you fire.
6. **Leaving mid-match counts as a loss.**

## 2. Round flow
1. **Drop-in, Call of Duty style.** Each round randomly picks a helicopter fast-rope, army truck, parachute jump, or armored car. You **choose your loadout during the ride**.
2. Fight.
3. **Round end:**
   - If the winning shot was a headshot, play a **slow-motion bullet cam**: the bullet cuts through the air, then **"HEADSHOT — CRITICAL HIT"**.
   - Then the **anime finisher**: freeze frame, dramatic zoom, speed lines, and the winner's name card slams in while the winner stands over the defeated player.
   - Headshots mid-round show only a quick red **"HEADSHOT"** flash and a ding, so play is never paused.
4. **Blood is anime ink only**: red slash marks and ink splatter, manga style. It must stay within Roblox's **Mild** maturity label so ages 9–15 can play. Realistic blood would push the game to Moderate and lock out Noelle's age group.

## 3. Maps
Medium-big maps with hiding spots that either team can use. Not mirrored, because side-swapping keeps them fair.

| Map | Setting |
|---|---|
| Shooting Range | Firing lanes, targets, a control tower |
| Desert Outpost | Sand, shipping containers, a watchtower |
| Urban Training Town | Fake practice houses for raid training |

Every map has:
- **Hills and dips** for crouch cover.
- **Two-story buildings** with windows.
- **One tall central tower**: best view, but exposed.

## 4. Weapons
Loadout = **1 primary + 1 sidearm + 1 melee + 1 gadget**. You re-pick it **every round**.

- **Primaries:** Assault rifle (all-rounder), SMG (fast, close range), Shotgun (one-shot up close, useless at range).
- **Sudden Death only:** Sniper, combat knife.
- **Gadgets:** Smoke grenade, Frag grenade, Med kit (+50 HP, 3 s channel, can't shoot while using it).
- **Starter pick:** on first join, choose your **starter weapon and its base color**.

Unlockables are **cosmetic only**. They have the same stats as the weapon they replace.
- **Double Trouble (Level 100):** twin dark-red swords with a glow, a red swing trail, and a *shing* when drawn. A melee option.
- **A Mother's Wrath (Level 300):** a dark-blue rifle that fires glowing blue shots, with its own blue-lightning cutscene on every elimination. Stats match the assault rifle.

## 5. Characters and hitboxes
1. Players use **their own Roblox avatar inside a standard team uniform** (helmet and vest). Everyone gets the same body size and the **same hitbox**, so tiny or skinny avatars give no advantage.
2. Teams: **Navy Blue vs Azure Grey**. Bright armbands (gold on Navy, white on Grey) keep the teams readable at range.
3. **100 HP.** Damage multipliers: **Head ×3, Body ×1, Legs ×0.5.**
4. Hitboxes are **exact**: they match the uniform body, with no padding.

## 6. Rewards and progression
**Coins** (earned only, never sold):

| Event | Coins |
|---|---|
| Win the match, final shot was a headshot | 120 |
| Win the match, final shot was a body shot | 80 |
| Lose the match | 10 per round won |
| First-ever join ("beginnersluck" message) | 350, **one time per account** |

**Coins buy:** weapon skins and anime finisher cutscenes. **All emotes are free** (handshakes, salutes).

**Levels and XP** come from wins, eliminations, and finishing matches.
- Level 100 should take about **2–3 weeks** of normal play.
- Level 50 unlocks **Ranked**.
- Level 100 unlocks **Double Trouble**.
- Level 200 unlocks the **"Eddie's Honor"** title and a gold salute emote.
- Level 300 unlocks **A Mother's Wrath**.

## 7. Anti-glitch: the server is the referee
The client never decides damage, ammo, hits, movement limits, coins, or XP.

| Exploit | Server defense |
|---|---|
| Shooting through walls | The server re-raycasts every claimed hit from the shooter's validated position |
| Aimbot / silent aim | The shot direction must match the server-tracked look direction within a tolerance |
| Infinite ammo / rapid fire | The server owns the magazine count and enforces the fire-rate cap |
| Speed, fly, teleport | The server checks movement deltas against max speed |
| Hiding in walls or under the map | Out-of-bounds volumes teleport the player back |
| Tiny avatars | Standard uniform hitbox (section 5) |
| Rejoin farming | Beginnersluck is one time per account; rewards are written server-side only |
| Rage-quitting | Leaving counts as a loss |

**Penalty: "Bot Bootcamp".** Flagged players are matched only against server-controlled bots. The server owns the bots, so cheats can't touch them, and they fight perfectly. To get out, a player must finish **3 clean matches in a row** (zero flags) or leave.

A **Report button** saves the last round's replay for review.

## 8. Lobby: Camp More Maniar
1. The lobby is a military-base courtyard named **Camp More Maniar** (a play on Noelle's last name, Moore, and on her being "more Maniar"). It has:
   - A **Shooting Range**: try any weapon for free.
   - The shop.
   - A leaderboard.
2. At the center is a **statue of Joanna and Eddie Moore side by side, holding hands**, with their names underneath.
3. The loading screen reads: **"Military Duels — dedicated to Joanna & Eddie Moore."**
4. **HUD colors:** on first join, each player picks their own color scheme (default Navy & Gold). It can be changed later in Settings.

## 9. Hard no's
- No real-money purchases. Coins are earned by playing only.
- Content must stay at Roblox's **Mild** maturity label or below.
- Unlockables never change weapon stats.
