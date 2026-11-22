--!strict
-- Every tunable in one place. Server and client both read this; only the server enforces it.

export type TeamId = "Navy" | "Grey"
export type Mode = "1v1" | "2v2"
-- Keys of Config.Weapons / Config.Gadgets. Plain strings: the server validates every incoming id
-- against Config.Loadout, and Luau widens literal unions as they pass through tables.
export type WeaponId = string
export type GadgetId = string
export type Role = "Sniper" | "Knife"

export type Weapon = {
	name: string,
	kind: "gun" | "melee",
	auto: boolean, -- hold to fire; otherwise one shot per click
	damage: number, -- body damage per bullet (or per stab) at close range
	pellets: number, -- bullets per trigger pull
	falloffStart: number,
	falloffEnd: number,
	minDamageScale: number, -- damage multiplier at and beyond falloffEnd
	range: number,
	fireInterval: number, -- seconds between shots (or swings)
	magazine: number, -- 0 for melee
	reloadTime: number,
	spreadHip: number, -- degrees
	spreadAim: number,
	spreadMoving: number, -- extra degrees while moving
	botRange: number, -- the bot closes in until it is this near
	scoped: boolean, -- aiming looks through a scope (sniper zoom and overlay)
}

export type Zone = string -- "Head" | "Body" | "Legs" (keys of ZoneMultiplier; produced only by Hitbox.cast)

local function gun(t: { [string]: any }): Weapon
	t.kind = t.kind or "gun"
	t.auto = if t.auto == nil then true else t.auto
	t.pellets = t.pellets or 1
	t.minDamageScale = t.minDamageScale or 0.7
	t.spreadMoving = t.spreadMoving or 1.5
	t.scoped = t.scoped == true
	return (t :: any) :: Weapon
end

local Config = {
	RoundsToWin = 5,
	SuddenDeathAt = 4,
	RoundSeconds = 120,
	FreezeSeconds = 10, -- the drop-in ride; the loadout is picked during it
	QueueSeconds = 10, -- after the first player queues for a map, others have this long to join
	RoundEndSeconds = 4, -- when no cutscene could be staged
	CutsceneGraceSeconds = 3, -- how long past a cutscene's length the server waits for slow clients
	MatchEndSeconds = 10, -- includes the match-win celebration
	SpawnShieldSeconds = 3,

	MaxHealth = 100,
	WalkSpeed = 16,
	AimWalkSpeed = 9,
	SprintSpeed = 24, -- hold Shift
	CrouchSpeed = 8, -- C toggles crouch
	SlideSpeed = 34, -- C while sprinting: a burst that slows to crouch speed
	SlideSeconds = 0.75,
	SlideCooldown = 1.2,
	CrouchHipHeight = 0.9, -- standing R15 HipHeight is 2; this drops the body about 1.1 studs
	DoubleJumpVelocity = 40, -- upward speed of the mid-air second jump (a normal jump is 42)
	JumpPower = 42,

	ZoneMultiplier = {
		Head = 3,
		Body = 1,
		Legs = 0.5,
	} :: { [Zone]: number },

	-- Standard uniform hitboxes, relative to HumanoidRootPart (offset, size) for a scale-1 R15 rig.
	-- Everyone gets these exact boxes no matter what avatar they wear.
	Hitboxes = {
		{ zone = "Head" :: Zone, offset = Vector3.new(0, 1.95, 0), size = Vector3.new(1.25, 1.25, 1.25) },
		{ zone = "Body" :: Zone, offset = Vector3.new(0, 0.45, 0), size = Vector3.new(2.6, 2.1, 1.2) },
		{ zone = "Legs" :: Zone, offset = Vector3.new(0, -1.75, 0), size = Vector3.new(1.8, 2.3, 1.1) },
	} :: { { zone: Zone, offset: Vector3, size: Vector3 } },

	-- Crouched: the root is ~1.1 studs lower, so the boxes are shorter and sit lower around it.
	CrouchHitboxes = {
		{ zone = "Head" :: Zone, offset = Vector3.new(0, 1.5, -0.15), size = Vector3.new(1.25, 1.25, 1.25) },
		{ zone = "Body" :: Zone, offset = Vector3.new(0, 0.35, 0), size = Vector3.new(2.6, 1.9, 1.4) },
		{ zone = "Legs" :: Zone, offset = Vector3.new(0, -1.0, 0), size = Vector3.new(1.8, 1.4, 1.6) },
	} :: { { zone: Zone, offset: Vector3, size: Vector3 } },

	-- One table for every weapon; the server enforces all of it.
	Weapons = {
		AR = gun({
			name = "Assault Rifle",
			damage = 25,
			falloffStart = 70,
			falloffEnd = 160,
			range = 600,
			fireInterval = 0.1,
			magazine = 30,
			reloadTime = 2.2,
			spreadHip = 2.2,
			spreadAim = 0.35,
			botRange = 80,
		}),
		SMG = gun({
			name = "SMG",
			damage = 21, -- 5 body shots: kills faster than the AR up close (0.26 s vs 0.30 s)
			falloffStart = 25,
			falloffEnd = 70,
			minDamageScale = 0.45,
			range = 400,
			fireInterval = 0.065,
			magazine = 35,
			reloadTime = 1.8,
			spreadHip = 3,
			spreadAim = 1.2,
			spreadMoving = 0.8,
			botRange = 35,
		}),
		Shotgun = gun({
			name = "Shotgun",
			auto = false,
			damage = 15, -- x8 pellets: 120 up close, so a point-blank blast wins
			pellets = 8,
			falloffStart = 10,
			falloffEnd = 32,
			minDamageScale = 0.1,
			range = 120,
			fireInterval = 0.85,
			magazine = 6,
			reloadTime = 2.6,
			spreadHip = 6,
			spreadAim = 4.5,
			spreadMoving = 0.5,
			botRange = 14,
		}),
		Pistol = gun({
			name = "Pistol",
			auto = false,
			damage = 30,
			falloffStart = 35,
			falloffEnd = 100,
			range = 400,
			fireInterval = 0.22,
			magazine = 12,
			reloadTime = 1.4,
			spreadHip = 1.5,
			spreadAim = 0.5,
			botRange = 40,
		}),
		Sniper = gun({
			name = "Sniper",
			auto = false,
			scoped = true,
			damage = 90, -- head x3 is a one-shot; body is two
			falloffStart = 1000,
			falloffEnd = 1001,
			minDamageScale = 1,
			range = 1000,
			fireInterval = 1.4,
			magazine = 5,
			reloadTime = 3,
			spreadHip = 7, -- aim down sights to be accurate
			spreadAim = 0,
			spreadMoving = 3,
			botRange = 200,
		}),
		Knife = gun({
			name = "Combat Knife",
			kind = "melee",
			auto = false,
			damage = 55, -- two stabs; the zone multiplier does not apply to melee
			falloffStart = 100,
			falloffEnd = 101,
			minDamageScale = 1,
			range = 7,
			fireInterval = 0.55,
			magazine = 0,
			reloadTime = 0,
			spreadHip = 0,
			spreadAim = 0,
			spreadMoving = 0,
			botRange = 4,
		}),
	} :: { [WeaponId]: Weapon },

	-- What the pre-round screen offers. The sidearm is always carried; the melee defaults to the knife.
	Loadout = {
		Primary = { "AR", "SMG", "Shotgun", "Sniper" } :: { WeaponId },
		Sidearm = "Pistol" :: WeaponId,
		Melee = "Knife" :: WeaponId,
		Gadget = { "Frag", "Smoke", "Medkit" } :: { GadgetId },
	},

	Gadgets = {
		Frag = { name = "Frag Grenade", fuse = 2.2, radius = 16, maxDamage = 110, minDamage = 20, throwSpeed = 75 },
		Smoke = { name = "Smoke Grenade", fuse = 1.2, radius = 12, duration = 12, throwSpeed = 75 },
		Medkit = { name = "Med Kit", heal = 50, channel = 3 },
	},

	-- HUD color themes, picked on first join and changed later in Settings. `primary` colors the panels,
	-- `accent` the highlights and gold text. The first one is the default.
	HudThemes = {
		{
			id = "NavyGold",
			name = "Navy & Gold",
			primary = Color3.fromRGB(16, 24, 48),
			accent = Color3.fromRGB(235, 190, 60),
		},
		{
			id = "CrimsonSilver",
			name = "Crimson & Silver",
			primary = Color3.fromRGB(64, 14, 20),
			accent = Color3.fromRGB(214, 218, 226),
		},
		{
			id = "ForestSand",
			name = "Forest & Sand",
			primary = Color3.fromRGB(26, 40, 24),
			accent = Color3.fromRGB(220, 196, 146),
		},
		{
			id = "MidnightCyan",
			name = "Midnight & Cyan",
			primary = Color3.fromRGB(10, 14, 32),
			accent = Color3.fromRGB(70, 214, 234),
		},
		{
			id = "PurplePink",
			name = "Purple & Pink",
			primary = Color3.fromRGB(42, 20, 64),
			accent = Color3.fromRGB(250, 128, 196),
		},
		{
			id = "BlackOrange",
			name = "Black & Orange",
			primary = Color3.fromRGB(16, 16, 18),
			accent = Color3.fromRGB(250, 146, 44),
		},
	} :: { { id: string, name: string, primary: Color3, accent: Color3 } },

	-- Roblox user ids of the game's developers. They own every skin and special weapon for free
	-- (looks only, so it gives no advantage in a duel).
	Developers = {
		[12015477852] = "hmania10",
		[11238400758] = "Aar0nBu44", -- Noelle, the game's designer
	} :: { [number]: string },

	-- XP and levels. A typical match (finish + some eliminations, a win half the time) is ~160 XP and
	-- lasts ~6 minutes; level 100 needs ~29,700 XP, about 185 matches or ~18 hours: about 1.5 hours a
	-- day for 2 weeks, or 1 hour a day for 3 weeks.
	Xp = {
		Finish = 50, -- for playing a match to the end
		Win = 100,
		Elimination = 20,
		Base = 100, -- XP from level L to L+1 is Base + PerLevel * L
		PerLevel = 4,
	},
	-- Level rewards. Unlocks are cosmetic or modes only; weapons keep the stats of their base weapon.
	Unlocks = {
		{ level = 50, kind = "Mode", id = "Ranked", name = "Ranked mode" },
		{ level = 100, kind = "Item", id = "DoubleTrouble", name = "Double Trouble" },
		{ level = 200, kind = "Title", id = "EddiesHonor", name = "Eddie's Honor title + gold salute" },
		{ level = 300, kind = "Item", id = "MothersWrath", name = "A Mother's Wrath" },
	} :: { { level: number, kind: string, id: string, name: string } },
	RankedStart = 1000, -- Rank Points for a new ranked player; a win moves 25 points from loser to winner
	RankedSwing = 25,

	-- Finisher inks (Shop > FINISHERS): the ink color of your round-win anime finisher's slashes and splatter.
	Finishers = {
		{ id = "Crimson", name = "Crimson Ink", price = 0, ink = Color3.fromRGB(200, 20, 30) },
		{ id = "Midnight", name = "Midnight Ink", price = 250, ink = Color3.fromRGB(40, 40, 120) },
		{ id = "Gold", name = "Golden Ink", price = 500, ink = Color3.fromRGB(235, 190, 60) },
		{ id = "Sakura", name = "Sakura Ink", price = 500, ink = Color3.fromRGB(250, 140, 190) },
		{ id = "Thunder", name = "Thunder Ink", price = 800, ink = Color3.fromRGB(70, 170, 255) },
	} :: { { id: string, name: string, price: number, ink: Color3 } },

	-- Free emotes for everyone: Roblox's default animations, or a pose built from code ("pose:").
	-- The gold salute needs the Eddie's Honor title.
	Emotes = {
		{ id = "Wave", name = "Wave", anim = "rbxassetid://507770239" },
		{ id = "Cheer", name = "Cheer", anim = "rbxassetid://507770677" },
		{ id = "Dance", name = "Dance", anim = "rbxassetid://507771019" },
		{ id = "Point", name = "Point", anim = "rbxassetid://507770453" },
		{ id = "Salute", name = "Gold Salute", anim = "pose:salute", title = "EddiesHonor" },
	} :: { { id: string, name: string, anim: string, title: string? } },

	-- First-join starter pick: a primary and its base color (a free starter skin for that weapon).
	Starter = {
		Weapons = { "AR", "SMG", "Shotgun", "Sniper" },
		Colors = { "DesertCamo", "ForestCamo", "ArcticWhite", "NavySteel" },
	},

	-- Coins (earned by playing only; never sold). Noelle's payout rules.
	Payouts = {
		WinHeadshot = 120, -- the match-winning shot was a headshot
		WinBody = 80, -- any other win, including the opponent leaving
		LoserPerRound = 10, -- per round the losing side won
		BeginnersLuck = 350, -- once per account, on the very first join
	},

	-- Weapon skins bought with coins. Cosmetic only: a skin never changes a weapon's stats. `color`
	-- is the swatch shown in the shop and inventory.
	Skins = {
		{ id = "Standard", name = "Standard", price = 0 },
		{
			id = "DesertCamo",
			name = "Desert Camo",
			price = 150,
			color = Color3.fromRGB(194, 170, 120),
			material = Enum.Material.Fabric,
		},
		{
			id = "ForestCamo",
			name = "Forest Camo",
			price = 150,
			color = Color3.fromRGB(74, 92, 58),
			material = Enum.Material.Fabric,
		},
		{
			id = "ArcticWhite",
			name = "Arctic White",
			price = 300,
			color = Color3.fromRGB(228, 232, 236),
			material = Enum.Material.SmoothPlastic,
		},
		{
			id = "NavySteel",
			name = "Navy Steel",
			price = 300,
			color = Color3.fromRGB(40, 58, 96),
			material = Enum.Material.Metal,
		},
		{
			id = "Crimson",
			name = "Crimson",
			price = 600,
			color = Color3.fromRGB(150, 24, 30),
			material = Enum.Material.SmoothPlastic,
		},
		{
			id = "Midnight",
			name = "Midnight Blue",
			price = 600,
			color = Color3.fromRGB(20, 28, 70),
			material = Enum.Material.Metal,
		},
		{
			id = "Gold",
			name = "Gold",
			price = 1000,
			color = Color3.fromRGB(212, 170, 60),
			material = Enum.Material.Foil,
		},
	} :: { { id: string, name: string, price: number, color: Color3?, material: Enum.Material? } },

	-- Weapons of their own bought with coins (Shop > WEAPONS). Once owned they appear in the loadout
	-- picker for their slot. Each copies the stats of its `base` weapon (see the copies after this
	-- table), so owning one is never an advantage.
	ShopWeapons = {
		{
			id = "DoubleTrouble",
			name = "Double Trouble",
			base = "Knife",
			price = 1500,
			slot = "Melee",
			color = Color3.fromRGB(120, 10, 16),
			blurb = "Twin dark katanas with glowing crimson edges, a red swing trail and a shing when drawn.",
		},
		{
			id = "MothersWrath",
			name = "A Mother's Wrath",
			base = "Sniper",
			price = 3000,
			slot = "Primary",
			color = Color3.fromRGB(16, 30, 90),
			blurb = "Dark-blue sniper rifle with glowing blue shots and blue lightning on every elimination.",
		},
	} :: {
		{
			id: string,
			name: string,
			base: WeaponId,
			price: number,
			slot: string,
			color: Color3,
			blurb: string,
		}
	},

	-- Arenas players can queue for from the Camp More Maniar lobby, in picker order.
	Maps = {
		{ id = "ShootingRange", name = "Shooting Range", blurb = "Firing lanes, offices and a tall control tower." },
		{ id = "DesertOutpost", name = "Desert Outpost", blurb = "Dunes, shipping containers and a watchtower." },
		{ id = "UrbanTown", name = "Urban Training Town", blurb = "Streets and houses built for raid practice." },
	},

	Teams = {
		Navy = {
			name = "NAVY",
			uniform = Color3.fromRGB(28, 42, 82),
			armband = Color3.fromRGB(235, 190, 60),
			hud = Color3.fromRGB(70, 110, 220),
		},
		Grey = {
			name = "GREY",
			uniform = Color3.fromRGB(128, 146, 166),
			armband = Color3.fromRGB(250, 250, 250),
			hud = Color3.fromRGB(180, 200, 220),
		},
	},

	-- Anti-cheat tolerances. Generous enough for normal lag, tight enough to catch tools.
	AntiCheat = {
		MaxOriginOffset = 5, -- studs between claimed muzzle origin and the server's head position
		MaxAimAngle = 30, -- degrees between shot direction and recent reported look direction
		LookWindow = 0.4, -- seconds of look history a shot may match
		LookRate = 30, -- max look updates per second (client sends about half that)
		MaxShotsPerSecond = 16, -- remote-level spam cap; per-weapon cadence is enforced in Combat.fire
		MaxRewind = 0.35, -- seconds of lag compensation
		MaxYawAngle = 60, -- degrees between shot yaw and the server-simulated body facing (fast flicks lag it)
		CheckInterval = 0.25,
	},

	Bot = {
		Name = "Recruit Bot",
		ReactionTime = 0.75, -- seconds from spotting you to the first shot
		AimErrorDegrees = 5, -- base miss cone; grows with distance. Settled: ~58% body hits at 20 studs, ~16% at 40
		AimSettleSeconds = 1.5, -- aim starts up to twice as wide and settles over this long
		MovingTargetPenalty = 1.6, -- extra miss cone against a running target
		SniperAimScale = 0.55, -- the sniper aims tighter, but not perfectly
		HeadshotChance = 0.07,
		RetreatHealth = 35, -- below this (or while reloading) the bot falls back to hidden cover
		HealBelow = 60, -- a bot carrying a med kit uses it in cover below this
		BurstShots = 4,
		BurstPause = 0.6,
		Think = 0.1,
	},

	Sounds = {
		Shot = "rbxassetid://2781019930",
		Hit = "rbxassetid://12222046",
		Headshot = "rbxassetid://12221990",
		Reload = "rbxassetid://12221976",
		Empty = "rbxassetid://12221976",
		Victory = "rbxassetid://12222253",
		Whoosh = "rbxassetid://12222095",
		Slash = "rbxassetid://12222095",
		Explosion = "rbxasset://sounds/impact_explosion_03.mp3",
	},
}

-- Shop weapons: their own ids, names and models, but copied stats, so "same stats" can't drift.
for _, entry in Config.ShopWeapons do
	local w = table.clone(Config.Weapons[entry.base])
	w.name = entry.name
	Config.Weapons[entry.id] = w
end

return Config
