--!strict
-- Registry of everyone in the current duel (players and bots), plus the server-side state the
-- client is never trusted with: ammo, reload, shield, position history for lag compensation,
-- recent look directions, and the last position the movement check accepted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type Combatant = {
	name: string,
	player: Player?,
	team: Config.TeamId,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	alive: boolean,
	ammo: number,
	reloadToken: number,
	reloading: boolean,
	lastShot: number,
	aiming: boolean,
	shieldUntil: number,
	historyT: { number },
	historyCF: { CFrame },
	looks: { { t: number, dir: Vector3 } },
	lastGrounded: CFrame,
	lastCheck: number,
}

local HISTORY_SECONDS = 1

local Combatants = {}

local list: { Combatant } = {}

function Combatants.new(name: string, player: Player?, team: Config.TeamId, model: Model, spawn: CFrame): Combatant
	local c: Combatant = {
		name = name,
		player = player,
		team = team,
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid,
		root = model:FindFirstChild("HumanoidRootPart") :: BasePart,
		alive = true,
		ammo = Config.AssaultRifle.magazine,
		reloadToken = 0,
		reloading = false,
		lastShot = 0,
		aiming = false,
		shieldUntil = 0,
		historyT = {},
		historyCF = {},
		looks = {},
		lastGrounded = spawn,
		lastCheck = os.clock(),
	}
	table.insert(list, c)
	Combatants.sync(c)
	return c
end

function Combatants.all(): { Combatant }
	return list
end

function Combatants.clear()
	for _, c in list do
		c.alive = false
		c.reloadToken += 1
		if c.player then
			c.player:SetAttribute("Ammo", nil)
			c.player:SetAttribute("Reloading", nil)
			c.player:SetAttribute("Shielded", nil)
		end
	end
	table.clear(list)
end

function Combatants.byPlayer(player: Player): Combatant?
	for _, c in list do
		if c.player == player then
			return c
		end
	end
	return nil
end

-- Mirror the state the HUD needs onto the player (read-only for the client).
function Combatants.sync(c: Combatant)
	local player = c.player
	if player then
		player:SetAttribute("Ammo", c.ammo)
		player:SetAttribute("Reloading", c.reloading)
		player:SetAttribute("Shielded", os.clock() < c.shieldUntil)
	end
end

-- Server-initiated moves reset the movement check so they never count as teleport hacks.
function Combatants.teleport(c: Combatant, cf: CFrame)
	c.model:PivotTo(cf)
	c.root.AssemblyLinearVelocity = Vector3.zero
	c.lastGrounded = cf
	c.lastCheck = os.clock()
	table.clear(c.historyT)
	table.clear(c.historyCF)
end

-- Where `c` was `secondsAgo` ago, interpolated from recorded history.
function Combatants.rewound(c: Combatant, secondsAgo: number): CFrame
	local times, cfs = c.historyT, c.historyCF
	local n = #times
	if n == 0 or secondsAgo <= 0 then
		return c.root.CFrame
	end
	local t = os.clock() - secondsAgo
	if t <= times[1] then
		return cfs[1]
	end
	for i = n, 2, -1 do
		if times[i - 1] <= t then
			local a = (t - times[i - 1]) / math.max(times[i] - times[i - 1], 1e-6)
			return cfs[i - 1]:Lerp(cfs[i], math.clamp(a, 0, 1))
		end
	end
	return cfs[n]
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, c in list do
		if c.alive and c.root.Parent then
			table.insert(c.historyT, now)
			table.insert(c.historyCF, c.root.CFrame)
			while #c.historyT > 2 and now - c.historyT[1] > HISTORY_SECONDS do
				table.remove(c.historyT, 1)
				table.remove(c.historyCF, 1)
			end
		end
		local shielded = now < c.shieldUntil
		if c.player and c.player:GetAttribute("Shielded") ~= shielded then
			c.player:SetAttribute("Shielded", shielded)
		end
	end
end)

return Combatants
