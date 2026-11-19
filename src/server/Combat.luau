--!strict
-- Server-authoritative shooting. Clients only send "I pulled the trigger from here, looking this
-- way". The server checks the claim, owns ammo, fire rate and spread, re-casts the shot against the
-- map and lag-compensated hitboxes, and applies damage.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheat = require(script.Parent.AntiCheat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(script.Parent.Net)

type Combatant = Combatants.Combatant

local WEAPON = Config.AssaultRifle
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

-- Bullets stop on map geometry and terrain, never on characters (hitboxes handle those).
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

function Combat.reload(c: Combatant)
	if not c.alive or c.reloading or c.ammo >= WEAPON.magazine then
		return
	end
	c.reloading = true
	c.reloadToken += 1
	local token = c.reloadToken
	Combatants.sync(c)
	task.delay(WEAPON.reloadTime, function()
		if c.reloadToken == token and c.alive then
			c.ammo = WEAPON.magazine
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
	if attacker.player then
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

-- One trigger pull. Bots are trusted; player claims are checked. Every shot is cast from the
-- server's validated head position; the client's origin only locates the crosshair's target.
function Combat.fire(c: Combatant, origin: Vector3, aimDir: Vector3)
	if not c.alive or not Combat.isLive() or c.reloading then
		return
	end
	if c.ammo <= 0 then
		Combat.reload(c)
		return
	end
	local now = os.clock()
	-- Same cadence for everyone. Players get 10% slack because their shots arrive with network jitter;
	-- a bunched shot is dropped, not flagged (the remote's token bucket flags real spam).
	if now - c.lastShot < WEAPON.fireInterval * (if c.player then 0.9 else 1) then
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
		local sight = workspace:Raycast(origin, aimDir * WEAPON.range, occlusion())
		local aimPoint = if sight then sight.Position else origin + aimDir * WEAPON.range
		local fromEye = aimPoint - Combat.headPosition(c)
		aimDir = if fromEye.Magnitude > 0.5 then fromEye else aimDir
	end
	origin = Combat.headPosition(c)

	c.lastShot = now
	c.ammo -= 1
	if c.shieldUntil > 0 then
		Combat.dropShield(c)
	end
	Combatants.sync(c)

	local velocity = c.root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 3
	local spread = (if c.aiming then WEAPON.spreadAim else WEAPON.spreadHip)
		+ (if moving then WEAPON.spreadMoving else 0)
	local dir = Hitbox.spread(aimDir.Unit, spread, rng)

	local wallHit = workspace:Raycast(origin, dir * WEAPON.range, occlusion())
	local maxDist = if wallHit then wallHit.Distance else WEAPON.range
	local rewind = if c.player then math.clamp(c.player:GetNetworkPing() + 0.05, 0, AC.MaxRewind) else 0

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

	local hitPos = origin + dir * victimDist
	Net.ShotFx:FireAllClients(c.model, origin, hitPos, victim == nil and wallHit ~= nil)
	if victim and victimZone then
		Combat.damage(victim, Hitbox.damage(WEAPON, victimZone, victimDist), c, victimZone)
	end
	if c.ammo <= 0 then
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
		-- Sustained rate is capped at the weapon's; the 2-shot burst only absorbs packet bunching.
		if not Net.allow(player, "Fire", AC.FireRateSlack / WEAPON.fireInterval, 2) then
			AntiCheat.flag(c, "Fire remote spam")
			return
		end
		Combat.fire(c, origin, dir)
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
