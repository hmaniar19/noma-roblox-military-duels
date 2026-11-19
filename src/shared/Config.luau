--!strict
-- Every tunable in one place. Server and client both read this; only the server enforces it.

export type TeamId = "Navy" | "Grey"

export type Weapon = {
	name: string,
	damage: number, -- body damage at close range
	falloffStart: number,
	falloffEnd: number,
	minDamageScale: number, -- damage multiplier at and beyond falloffEnd
	range: number,
	fireInterval: number, -- seconds between shots
	magazine: number,
	reloadTime: number,
	spreadHip: number, -- degrees
	spreadAim: number,
	spreadMoving: number, -- extra degrees while moving
}

export type Zone = "Head" | "Body" | "Legs"

local Config = {
	RoundsToWin = 5,
	SuddenDeathAt = 4,
	RoundSeconds = 120,
	FreezeSeconds = 3,
	RoundEndSeconds = 4,
	MatchEndSeconds = 8,
	SpawnShieldSeconds = 3,

	MaxHealth = 100,
	WalkSpeed = 16,
	AimWalkSpeed = 9,
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

	AssaultRifle = {
		name = "Assault Rifle",
		damage = 25,
		falloffStart = 70,
		falloffEnd = 160,
		minDamageScale = 0.7,
		range = 600,
		fireInterval = 0.1,
		magazine = 30,
		reloadTime = 2.2,
		spreadHip = 2.2,
		spreadAim = 0.35,
		spreadMoving = 1.5,
	} :: Weapon,

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
		LookRate = 20, -- max look updates per second
		FireRateSlack = 1.15, -- allowed sustained shots/s = this / fireInterval (burst of 3 for jitter)
		MaxRewind = 0.35, -- seconds of lag compensation
		SpeedSlack = 1.6, -- multiplier on allowed horizontal speed
		SpeedGrace = 4, -- studs of free movement per check
		CheckInterval = 0.25,
		MaxAirSeconds = 2.5, -- rising/hovering longer than this is flying
	},

	Bot = {
		Name = "Recruit Bot",
		ReactionTime = 0.45,
		AimErrorDegrees = 3.2, -- grows with distance
		HeadshotChance = 0.18,
		BurstShots = 5,
		BurstPause = 0.35,
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
	},
}

return Config
