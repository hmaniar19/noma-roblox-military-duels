--!strict
-- Server-authoritative weapons. Clients only send "I pulled the trigger from here, looking this
-- way" and "switch to slot N". The server checks the claim, owns the arsenal, ammo, fire rate and
-- spread, re-casts every bullet against the map and lag-compensated hitboxes, and applies damage.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheat = require(script.Parent.AntiCheat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Net = require(script.Parent.Net)
local Report = require(script.Parent.Report)

type Combatant = Combatants.Combatant

local AC = Config.AntiCheat
local HEAD_OFFSET = Config.Hitboxes[1].offset

local Combat = {}

-- A combatant can only fight while its own arena's round is live (several arenas run at once).
function Combat.isLive(c: Combatant): boolean
	return c.arena.isLive()
end

local rng = Random.new()
local fxFolder = Instance.new("Folder")
fxFolder.Name = "Fx"
fxFolder.Parent = workspace

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

-- Bullets stop on map geometry and terrain, never on characters (hitboxes handle those) or smoke.
local function occlusion(): RaycastParams
	local ignore: { Instance } = { fxFolder }
	for _, c in Combatants.all() do
		table.insert(ignore, c.model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end
Combat.occlusion = occlusion
Combat.fxFolder = fxFolder

local function headAt(cf: CFrame, crouched: boolean): Vector3
	return (cf * CFrame.new(if crouched then Config.CrouchHitboxes[1].offset else HEAD_OFFSET)).Position
end

function Combat.headPosition(c: Combatant): Vector3
	return headAt(c.root.CFrame, c.stance == "Crouch")
end

function Combat.dropShield(c: Combatant)
	c.shieldUntil = 0
	local field = c.model:FindFirstChildOfClass("ForceField")
	if field then
		field:Destroy()
	end
end

-- Movement speed from stance, aiming and slide. The server owns it (Server Authority predicts it).
function Combat.applySpeed(c: Combatant)
	if not c.alive or os.clock() < c.slideUntil then
		return
	end
	c.humanoid.WalkSpeed = if c.stance == "Crouch"
		then Config.CrouchSpeed
		elseif c.aiming then Config.AimWalkSpeed
		elseif c.stance == "Sprint" then Config.SprintSpeed
		else Config.WalkSpeed
end

local standingPose: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local LEG_BENDS: { [string]: number } = { LeftHip = 70, RightHip = 70, LeftKnee = -110, RightKnee = -110 }

-- Crouching lowers the body (HipHeight) and bends hips and knees so the legs fold instead of sinking
-- into the ground. Hit detection switches to Config.CrouchHitboxes.
local function crouchPose(c: Combatant, crouched: boolean)
	c.humanoid.HipHeight = if crouched then Config.CrouchHipHeight else 2
	for name, degrees in LEG_BENDS do
		local joint = c.model:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			standingPose[joint] = standingPose[joint] or joint.C0
			joint.C0 = if crouched
				then standingPose[joint] * CFrame.Angles(math.rad(degrees), 0, 0)
				else standingPose[joint]
		end
	end
end

function Combat.setStance(c: Combatant, stance: "Stand" | "Sprint" | "Crouch")
	if not c.alive or c.stance == stance then
		return
	end
	if (stance == "Crouch") ~= (c.stance == "Crouch") then
		crouchPose(c, stance == "Crouch")
	end
	c.stance = stance
	Combat.applySpeed(c)
	Combatants.sync(c)
end

-- Sprint + C: a burst of speed that bleeds off into a crouch.
function Combat.slide(c: Combatant)
	local now = os.clock()
	if c.stance ~= "Sprint" or now - c.lastSlide < Config.SlideCooldown then
		return
	end
	if c.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	c.lastSlide = now
	Combat.setStance(c, "Crouch")
	c.slideUntil = now + Config.SlideSeconds
	task.spawn(function()
		while c.alive and os.clock() < c.slideUntil do
			local k = (c.slideUntil - os.clock()) / Config.SlideSeconds
			c.humanoid.WalkSpeed = Config.CrouchSpeed + (Config.SlideSpeed - Config.CrouchSpeed) * k
			task.wait(0.05)
		end
		Combat.applySpeed(c)
	end)
end

-- One extra jump in mid-air, recharged on landing. The server applies the push, so it can't be spammed.
function Combat.doubleJump(c: Combatant)
	if not c.alive or c.doubleJumped or c.humanoid.FloorMaterial ~= Enum.Material.Air then
		return
	end
	c.doubleJumped = true
	local v = c.root.AssemblyLinearVelocity
	c.root.AssemblyLinearVelocity = Vector3.new(v.X, Config.DoubleJumpVelocity, v.Z)
	if c.stance == "Crouch" then
		Combat.setStance(c, "Stand")
	end
end

-- Puts the weapon in slot `index` in the combatant's hands (a fresh Tool built from the shared model).
function Combat.equip(c: Combatant, index: number)
	local id = c.weapons[index]
	if not id or not c.alive then
		return
	end
	c.equipped = index
	c.reloadToken += 1 -- switching cancels a reload
	c.reloading = false
	-- Aim survives a swap to another aimable weapon; the client resends Aim if its state differs.
	c.aiming = c.aiming and Config.Weapons[id].kind ~= "melee"
	Combat.applySpeed(c)
	for _, child in c.model:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	local tool = Instance.new("Tool")
	tool.Name = Config.Weapons[id].name
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = Gun.Grip
	-- The owner's equipped skin (published by Economy); bots carry standard guns.
	local skin = if c.player then Profile.skin(c.player, id) else nil
	local handle = Gun.build(tool, id, skin)
	tool.Parent = c.model
	c.humanoid:EquipTool(tool)
	local draw = handle:FindFirstChild("Draw")
	if draw and draw:IsA("Sound") then
		draw:Play() -- Double Trouble's shing
	end
	Combatants.sync(c)
end

-- Gives a fresh arsenal: full magazines, slot 1 in hand, one gadget charge.
function Combat.arm(c: Combatant, weapons: { Config.WeaponId }, gadget: Config.GadgetId?)
	c.weapons = weapons
	table.clear(c.ammo)
	for _, id in weapons do
		c.ammo[id] = Config.Weapons[id].magazine
	end
	c.gadget = gadget
	c.gadgetLeft = if gadget then 1 else 0
	c.healingUntil = 0
	Combat.equip(c, 1)
end

function Combat.reload(c: Combatant)
	local id = Combatants.weapon(c)
	if not id or not c.alive or c.reloading or c.healingUntil > 0 then
		return
	end
	local w = Config.Weapons[id]
	if w.kind ~= "gun" or c.ammo[id] >= w.magazine then
		return
	end
	c.reloading = true
	c.reloadToken += 1
	local token = c.reloadToken
	Combatants.sync(c)
	task.delay(w.reloadTime, function()
		if c.reloadToken == token and c.alive then
			c.ammo[id] = w.magazine
			c.reloading = false
			Combatants.sync(c)
		end
	end)
end

-- A Mother's Wrath elimination: a jagged blue lightning bolt strikes the target from the sky.
local function wrathStrike(at: Vector3)
	local points = { at + Vector3.new(0, 60, 0) }
	for i = 1, 7 do
		local y = 60 - i * 60 / 8
		table.insert(points, at + Vector3.new(rng:NextNumber(-3, 3), y, rng:NextNumber(-3, 3)))
	end
	table.insert(points, at)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local bolt = Instance.new("Part")
		bolt.Anchored, bolt.CanCollide, bolt.CanQuery, bolt.CanTouch, bolt.CastShadow = true, false, false, false, false
		bolt.Material = Enum.Material.Neon
		bolt.Color = Color3.fromRGB(110, 180, 255)
		bolt.Size = Vector3.new(0.5, 0.5, (b - a).Magnitude)
		bolt.CFrame = CFrame.lookAt((a + b) / 2, b)
		bolt.Parent = fxFolder
		task.delay(0.5, bolt.Destroy, bolt)
	end
	local glow = Instance.new("Part")
	glow.Anchored, glow.CanCollide, glow.CanQuery, glow.CanTouch = true, false, false, false
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(70, 150, 255)
	glow.Transparency = 0.4
	glow.Size = Vector3.new(7, 7, 7)
	glow.Position = at
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = Color3.fromRGB(110, 180, 255), 8, 30
	light.Parent = glow
	glow.Parent = fxFolder
	task.delay(0.5, glow.Destroy, glow)
end

-- Returns nil if the hit was blocked, else whether it killed. `quiet` skips the hit/hurt
-- notifications so a multi-pellet shot can send one of each.
function Combat.damage(
	target: Combatant,
	amount: number,
	attacker: Combatant,
	zone: Config.Zone,
	weapon: string?,
	quiet: boolean?
): boolean?
	if not target.alive or os.clock() < target.shieldUntil then
		return nil
	end
	local humanoid = target.humanoid
	humanoid.Health = math.max(0, humanoid.Health - amount)
	local killed = humanoid.Health <= 0
	if target.healingUntil > 0 then
		target.healingUntil = 0 -- taking damage interrupts a med kit
		Combatants.sync(target)
	end
	if killed then
		target.alive = false
		if weapon == "MothersWrath" then
			wrathStrike(target.root.Position)
		end
		target.arena.onElimination(target, attacker, zone, weapon)
	end
	if not quiet then
		Combat.notify(attacker, target, zone, killed, amount)
	end
	return killed
end

function Combat.notify(attacker: Combatant, target: Combatant, zone: Config.Zone?, killed: boolean, amount: number)
	local hitBy, hurt = attacker.player, target.player
	if zone and hitBy and attacker ~= target and hitBy.Parent ~= nil then
		pcall(Net.HitConfirm.FireClient, Net.HitConfirm, hitBy, zone, killed)
	end
	if hurt and hurt.Parent ~= nil then
		pcall(Net.Damaged.FireClient, Net.Damaged, hurt, attacker.root.Position, amount)
	end
end

local ORIGIN_SAMPLES: { number } = { 0.1, 0.2, 0.35 }
local MAX_SPEED = math.max(Config.SprintSpeed, Config.SlideSpeed) * 1.25

-- Validates a shot claim from a player. Returns the reason it was rejected, or nil.
-- Call after AntiCheat.validate so the root (and so the head) is a position the server accepted.
-- The client fired from where it was up to a ping ago, so the origin is compared with the nearest of
-- the current and recently rewound heads, plus what its current speed covers in that window.
local function rejectClaim(c: Combatant, origin: Vector3, dir: Vector3): string?
	local player = c.player :: Player
	local speed = math.min(c.root.AssemblyLinearVelocity.Magnitude, MAX_SPEED)
	local slack = AC.MaxOriginOffset + speed * math.min(player:GetNetworkPing(), AC.MaxRewind)
	local offset = (origin - Combat.headPosition(c)).Magnitude
	for _, t in ORIGIN_SAMPLES do
		local cf, crouched = Combatants.rewound(c, math.min(t, AC.MaxRewind))
		offset = math.min(offset, (origin - headAt(cf, crouched)).Magnitude)
	end
	if offset > slack then
		return `shot origin {math.floor(offset)} studs from validated head`
	end
	if not AntiCheat.aimMatches(c, dir) then
		return "shot direction does not match look direction"
	end
	return nil
end

-- Nearest living enemy hitbox along a ray, at the shooter's view of the past (`rewind` seconds).
local function trace(
	c: Combatant,
	origin: Vector3,
	dir: Vector3,
	maxDist: number,
	rewind: number
): (Combatant?, Config.Zone?, number)
	local victim: Combatant? = nil
	local victimZone: Config.Zone? = nil
	local victimDist = maxDist
	for _, other in Combatants.all() do
		if other ~= c and other.arena == c.arena and other.alive and other.team ~= c.team then
			local cf, crouched = Combatants.rewound(other, rewind)
			local zone: Config.Zone?, dist: number? = Hitbox.cast(origin, dir, maxDist, cf, crouched)
			if zone and dist and dist <= victimDist then
				victim, victimZone, victimDist = other, zone :: Config.Zone, dist
			end
		end
	end
	return victim, victimZone, victimDist
end

-- One trigger pull (or knife swing). Bots are trusted; player claims are checked. Every shot is cast
-- from the server's validated head position; the client's origin only locates the crosshair's target.
function Combat.fire(c: Combatant, origin: Vector3, aimDir: Vector3)
	local id = Combatants.weapon(c)
	if not id or not c.alive or not Combat.isLive(c) or c.reloading or c.healingUntil > 0 then
		return
	end
	local w = Config.Weapons[id]
	if w.kind == "gun" and c.ammo[id] <= 0 then
		Combat.reload(c)
		return
	end
	local now = os.clock()
	-- Every weapon's cadence applies to everyone. Players get 10% slack for network jitter; a
	-- bunched shot is dropped, not flagged (the remote's token bucket flags real spam).
	if now - c.lastShot < w.fireInterval * (if c.player then 0.9 else 1) then
		return
	end
	if c.player then
		if AntiCheat.validate(c) then
			return -- fired from a position the server just corrected
		end
		local reason = rejectClaim(c, origin, aimDir)
		if reason == "shot direction does not match look direction" then
			AntiCheat.flagAim(c, aimDir, reason)
		elseif reason then
			AntiCheat.flag(c, reason)
		end
		if reason then
			return
		end
		-- Aim at what's under the crosshair, then shoot it from the server's eye so the small
		-- camera/eye parallax can't send a clear-looking shot into a wall edge.
		local sight = workspace:Raycast(origin, aimDir * w.range, occlusion())
		local aimPoint = if sight then sight.Position else origin + aimDir * w.range
		local fromEye = aimPoint - Combat.headPosition(c)
		-- The re-aimed ray may only correct camera/eye parallax (a few degrees), never steer the shot:
		-- otherwise a spoofed origin could bend an aim-checked direction toward a target.
		if fromEye.Magnitude > 0.5 and Hitbox.angleBetween(fromEye.Unit, aimDir) <= 10 then
			aimDir = fromEye
		end
	end
	origin = Combat.headPosition(c)
	aimDir = aimDir.Unit

	c.lastShot = now
	if c.stance == "Sprint" then
		Combat.setStance(c, "Stand") -- no shooting at full sprint
	end
	if c.shieldUntil > 0 then
		Combat.dropShield(c)
	end
	local rewind = if c.player then math.clamp(c.player:GetNetworkPing() + 0.05, 0, AC.MaxRewind) else 0

	if w.kind == "melee" then
		-- A stab reaches `range` studs and is stopped by walls. Melee ignores zone multipliers.
		local wall = workspace:Raycast(origin, aimDir * w.range, occlusion())
		local victim, zone = trace(c, origin, aimDir, if wall then wall.Distance else w.range, rewind)
		Net.ShotFx:FireAllClients(c.model, origin, origin, false, true, true)
		Report.shot(c, origin, aimDir, if victim then victim.name else nil, zone)
		if victim and zone then
			Combat.damage(victim, w.damage, c, zone :: Config.Zone, id)
		end
		return
	end

	c.ammo[id] -= 1
	Combatants.sync(c)
	local velocity = c.root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 3
	local spread = if c.perfect
		then 0
		else (if c.aiming then w.spreadAim else w.spreadHip) + (if moving then w.spreadMoving else 0)
	local RANK = { Head = 3, Body = 2, Legs = 1 }
	local dealt: { [Combatant]: number } = {}
	local bestZone: Config.Zone?, anyKilled, firstVictim: string? = nil, false, nil
	for pellet = 1, w.pellets do
		local dir = Hitbox.spread(aimDir, spread, rng)
		local wallHit = workspace:Raycast(origin, dir * w.range, occlusion())
		local victim, zone, dist = trace(c, origin, dir, if wallHit then wallHit.Distance else w.range, rewind)
		local hitWall = victim == nil and wallHit ~= nil
		Net.ShotFx:FireAllClients(c.model, origin, origin + dir * dist, hitWall, false, pellet == 1)
		if victim and zone then
			-- Before damage: a killing hit may start the bullet cam, which reads these.
			c.lastShotFrom, c.lastShotHit = origin, origin + dir * dist
			local hitZone = zone :: Config.Zone
			local amount = Hitbox.damage(w, hitZone, dist)
			local killed = Combat.damage(victim, amount, c, hitZone, id, true)
			if killed ~= nil then
				dealt[victim] = (dealt[victim] or 0) + amount
				firstVictim = firstVictim or victim.name
				anyKilled = anyKilled or killed
				if not bestZone or (RANK[hitZone] or 0) > (RANK[bestZone] or 0) then
					bestZone = hitZone
				end
			end
		end
	end
	Report.shot(c, origin, aimDir, firstVictim, bestZone)
	-- One hit marker for the shooter, one damage event per victim.
	for victim, amount in dealt do
		Combat.notify(c, victim, bestZone, anyKilled, amount)
		bestZone = nil
	end
	if c.ammo[id] <= 0 then
		Combat.reload(c)
	end
end

function Combat.bind()
	Net.Fire.OnServerEvent:Connect(function(player, origin, dir)
		local c = Combatants.byPlayer(player)
		if not c then
			return
		end
		-- Remote-level spam cap first, so malformed spam is capped too; weapon cadence is in Combat.fire.
		-- Network hitches deliver shots in bunches, so extra packets are just dropped; only a flood far
		-- beyond any weapon (a second, much looser bucket) counts as a cheat flag.
		if not Net.allow(player, "Fire", AC.MaxShotsPerSecond, 8) then
			if not Net.allow(player, "FireFlood", AC.MaxShotsPerSecond, 24) then
				AntiCheat.flag(c, "Fire remote spam")
			end
			return
		end
		if not Net.isVector(origin, 1e4) or not Net.isDirection(dir) then
			AntiCheat.flag(c, "malformed Fire payload")
			return
		end
		Combat.fire(c, origin, dir)
	end)
	Net.Equip.OnServerEvent:Connect(function(player, index)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Equip", 8, 3) then
			return
		end
		if typeof(index) ~= "number" or index ~= index // 1 or not c.weapons[index] then
			AntiCheat.flag(c, "malformed Equip payload")
			return
		end
		if index ~= c.equipped and c.healingUntil == 0 then
			Combat.equip(c, index)
		end
	end)
	Net.Reload.OnServerEvent:Connect(function(player)
		local c = Combatants.byPlayer(player)
		if c and Net.allow(player, "Reload", 2, 2) and Combat.isLive(c) then
			Combat.reload(c)
		end
	end)
	Net.Aim.OnServerEvent:Connect(function(player, aiming)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Aim", 10, 5) or not Combat.isLive(c) then
			return
		end
		if typeof(aiming) ~= "boolean" then
			AntiCheat.flag(c, "malformed Aim payload")
			return
		end
		c.aiming = aiming
		if aiming and c.stance == "Sprint" then
			Combat.setStance(c, "Stand")
		end
		Combat.applySpeed(c)
	end)
	Net.Stance.OnServerEvent:Connect(function(player, stance)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Stance", 10, 5) or not Combat.isLive(c) then
			return
		end
		if stance == "Slide" then
			Combat.slide(c)
		elseif stance == "DoubleJump" then
			Combat.doubleJump(c)
		elseif stance == "Stand" or stance == "Crouch" or stance == "Sprint" then
			if not (stance == "Sprint" and c.aiming) then
				Combat.setStance(c, stance)
			end
		else
			AntiCheat.flag(c, "malformed Stance payload")
		end
	end)
	Net.Look.OnServerEvent:Connect(function(player, dir)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Look", AC.LookRate, 5) then
			return
		end
		if not Net.isDirection(dir) then
			AntiCheat.flag(c, "malformed Look payload")
			return
		end
		AntiCheat.recordLook(c, dir)
	end)
end

return Combat
