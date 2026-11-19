--!strict
-- Server-side checks on what players claim: aim direction vs reported look, and movement
-- (speed, flying, leaving the map). Every rejection adds a cheat flag; penalties come in phase 6.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Hitbox)

local AC = Config.AntiCheat

local AntiCheat = {}

export type Flag = { t: number, reason: string }
local log: { [Player]: { Flag } } = {}

function AntiCheat.flag(c: Combatants.Combatant, reason: string)
	local player = c.player
	if not player then
		return
	end
	local entries = log[player] or {}
	log[player] = entries
	table.insert(entries, { t = os.time(), reason = reason })
	player:SetAttribute("CheatFlags", #entries)
	warn(`[AntiCheat] {player.Name} ({player.UserId}): {reason}`)
end

function AntiCheat.flags(player: Player): { Flag }
	return log[player] or {}
end

function AntiCheat.recordLook(c: Combatants.Combatant, dir: Vector3)
	local now = os.clock()
	table.insert(c.looks, { t = now, dir = dir })
	while #c.looks > 1 and now - c.looks[1].t > 1 do
		table.remove(c.looks, 1)
	end
end

-- A shot must point roughly where the player was actually looking a moment ago. Stops silent aim,
-- where a tool fires at the enemy while the camera points somewhere else.
function AntiCheat.aimMatches(c: Combatants.Combatant, dir: Vector3): boolean
	local now = os.clock()
	for i = #c.looks, 1, -1 do
		local look = c.looks[i]
		if now - look.t > AC.LookWindow then
			break
		end
		if Hitbox.angleBetween(look.dir, dir) <= AC.MaxAimAngle then
			return true
		end
	end
	return false
end

local function inside(p: Vector3, lo: Vector3, hi: Vector3): boolean
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

local function check(c: Combatants.Combatant, now: number, boundsMin: Vector3, boundsMax: Vector3)
	local dt = now - c.lastCheck
	if dt < AC.CheckInterval then
		return
	end
	c.lastCheck = now
	local root, humanoid = c.root, c.humanoid
	local pos = root.Position

	if not inside(pos, boundsMin, boundsMax) then
		-- Falling off is not cheating; getting above the ceiling or through the walls is.
		if pos.Y >= boundsMin.Y then
			AntiCheat.flag(c, `out of bounds at {math.floor(pos.X)},{math.floor(pos.Y)},{math.floor(pos.Z)}`)
		end
		Combatants.teleport(c, c.lastGrounded)
		return
	end

	local moved = Vector3.new(pos.X - c.lastValid.X, 0, pos.Z - c.lastValid.Z).Magnitude
	local allowed = Config.WalkSpeed * dt * AC.SpeedSlack + AC.SpeedGrace
	if moved > allowed then
		AntiCheat.flag(c, `speed {math.floor(moved / dt)} studs/s`)
		Combatants.teleport(c, c.lastValid)
		return
	end
	c.lastValid = root.CFrame

	local state = humanoid:GetState()
	local supported = humanoid.FloorMaterial ~= Enum.Material.Air
		or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming
	if supported then
		c.airTime = 0
		c.lastGrounded = root.CFrame
	elseif root.AssemblyLinearVelocity.Y > -2 then
		c.airTime += dt
		if c.airTime > AC.MaxAirSeconds then
			AntiCheat.flag(c, "flying")
			Combatants.teleport(c, c.lastGrounded)
		end
	end
end

function AntiCheat.start(boundsMin: Vector3, boundsMax: Vector3)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, c in Combatants.all() do
			if c.player and c.alive and not c.root.Anchored and c.root.Parent then
				check(c, now, boundsMin, boundsMax)
			end
		end
	end)
end

return AntiCheat
