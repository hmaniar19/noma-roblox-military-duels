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
local Net = require(script.Parent.Net)

type Combatant = Combatants.Combatant

local AC = Config.AntiCheat
local HEAD_OFFSET = Config.Hitboxes[1].offset

local Combat = {}

-- Set by Match.
Combat.isLive = function(): boolean
	return false
end
Combat.onElimination = function(_victim: Combatant, _attacker: Combatant?, _zone: Config.Zone?) end

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

function Combat.headPosition(c: Combatant): Vector3
	return (c.root.CFrame * CFrame.new(HEAD_OFFSET)).Position
end

function Combat.dropShield(c: Combatant)
	c.shieldUntil = 0
	local field = c.model:FindFirstChildOfClass("ForceField")
	if field then
		field:Destroy()
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
	c.aiming = false
	c.humanoid.WalkSpeed = Config.WalkSpeed
	for _, child in c.model:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
	local tool = Instance.new("Tool")
	tool.Name = Config.Weapons[id].name
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.new(0, -0.1, 0.2) * CFrame.Angles(0, math.rad(180), 0)
	Gun.build(tool, id)
	tool.Parent = c.model
	c.humanoid:EquipTool(tool)
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
	if not id or not c.alive or c.reloading then
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

function Combat.damage(target: Combatant, amount: number, attacker: Combatant, zone: Config.Zone)
	if not target.alive or os.clock() < target.shieldUntil then
		return
	end
	local humanoid = target.humanoid
	humanoid.Health = math.max(0, humanoid.Health - amount)
	local killed = humanoid.Health <= 0
	if target.healingUntil > 0 then
		target.healingUntil = 0 -- taking damage interrupts a med kit
		Combatants.sync(target)
	end
	if attacker.player and attacker ~= target then
		Net.HitConfirm:FireClient(attacker.player, zone, killed)
	end
	if target.player then
		Net.Damaged:FireClient(target.player, attacker.root.Position, amount)
	end
	if killed then
		target.alive = false
		Combat.onElimination(target, attacker, zone)
	end
end

-- Validates a shot claim from a player. Returns the reason it was rejected, or nil.
-- Call after AntiCheat.validate so the root (and so the head) is a position the server accepted.
local function rejectClaim(c: Combatant, origin: Vector3, dir: Vector3): string?
	local head = Combat.headPosition(c)
	local player = c.player :: Player
	local slack = AC.MaxOriginOffset + Config.WalkSpeed * math.min(player:GetNetworkPing(), AC.MaxRewind)
	local offset = (origin - head).Magnitude
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
		if other ~= c and other.alive and other.team ~= c.team then
			local zone: Config.Zone?, dist: number? =
				Hitbox.cast(origin, dir, maxDist, Combatants.rewound(other, rewind))
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
	if not id or not c.alive or not Combat.isLive() or c.reloading or c.healingUntil > 0 then
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
		AntiCheat.validate(c)
		local reason = rejectClaim(c, origin, aimDir)
		if reason then
			AntiCheat.flag(c, reason)
			return
		end
		-- Aim at what's under the crosshair, then shoot it from the server's eye so the small
		-- camera/eye parallax can't send a clear-looking shot into a wall edge.
		local sight = workspace:Raycast(origin, aimDir * w.range, occlusion())
		local aimPoint = if sight then sight.Position else origin + aimDir * w.range
		local fromEye = aimPoint - Combat.headPosition(c)
		aimDir = if fromEye.Magnitude > 0.5 then fromEye else aimDir
	end
	origin = Combat.headPosition(c)
	aimDir = aimDir.Unit

	c.lastShot = now
	if c.shieldUntil > 0 then
		Combat.dropShield(c)
	end
	local rewind = if c.player then math.clamp(c.player:GetNetworkPing() + 0.05, 0, AC.MaxRewind) else 0

	if w.kind == "melee" then
		-- A stab reaches `range` studs and is stopped by walls. Melee ignores zone multipliers.
		local wall = workspace:Raycast(origin, aimDir * w.range, occlusion())
		local victim, zone = trace(c, origin, aimDir, if wall then wall.Distance else w.range, rewind)
		Net.ShotFx:FireAllClients(c.model, origin, origin, false, true)
		if victim and zone then
			Combat.damage(victim, w.damage, c, zone :: Config.Zone)
		end
		return
	end

	c.ammo[id] -= 1
	Combatants.sync(c)
	local velocity = c.root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 3
	local spread = (if c.aiming then w.spreadAim else w.spreadHip) + (if moving then w.spreadMoving else 0)
	for _ = 1, w.pellets do
		local dir = Hitbox.spread(aimDir, spread, rng)
		local wallHit = workspace:Raycast(origin, dir * w.range, occlusion())
		local victim, zone, dist = trace(c, origin, dir, if wallHit then wallHit.Distance else w.range, rewind)
		Net.ShotFx:FireAllClients(c.model, origin, origin + dir * dist, victim == nil and wallHit ~= nil, false)
		if victim and zone then
			local hitZone = zone :: Config.Zone
			Combat.damage(victim, Hitbox.damage(w, hitZone, dist), c, hitZone)
		end
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
		if not Net.isVector(origin, 1e4) or not Net.isDirection(dir) then
			AntiCheat.flag(c, "malformed Fire payload")
			return
		end
		-- Remote-level spam cap; each weapon's own cadence is enforced in Combat.fire.
		if not Net.allow(player, "Fire", AC.MaxShotsPerSecond, 2) then
			AntiCheat.flag(c, "Fire remote spam")
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
		if c and Net.allow(player, "Reload", 2, 2) then
			Combat.reload(c)
		end
	end)
	Net.Aim.OnServerEvent:Connect(function(player, aiming)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Aim", 10, 5) then
			return
		end
		if typeof(aiming) ~= "boolean" then
			AntiCheat.flag(c, "malformed Aim payload")
			return
		end
		c.aiming = aiming
		if c.alive then
			c.humanoid.WalkSpeed = if aiming then Config.AimWalkSpeed else Config.WalkSpeed
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
