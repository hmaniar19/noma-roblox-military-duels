--!strict
-- The gadget slot: one charge per round. Frag grenades explode with distance falloff and walls block
-- the blast; smoke grenades leave a cloud that hides players from each other (and from bots, whose
-- line-of-sight checks use smokeBlocks); the med kit heals over a channel that damage interrupts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AntiCheat = require(script.Parent.AntiCheat)
local Combat = require(script.Parent.Combat)
local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

type Combatant = Combatants.Combatant

local G = Config.Gadgets
local BODY_OFFSET = Config.Hitboxes[2].offset

local Gadgets = {}

type Cloud = { center: Vector3, radius: number, ends: number }
local clouds: { Cloud } = {}
local folder = Instance.new("Folder")
folder.Name = "Gadgets"
folder.Parent = workspace

-- True if the segment from `a` to `b` passes through an active smoke cloud.
function Gadgets.smokeBlocks(a: Vector3, b: Vector3): boolean
	local now = os.clock()
	local d = b - a
	for _, cloud in clouds do
		if now < cloud.ends then
			local t = math.clamp((cloud.center - a):Dot(d) / math.max(d:Dot(d), 1e-6), 0, 1)
			if (a + d * t - cloud.center).Magnitude < cloud.radius then
				return true
			end
		end
	end
	return false
end

local function explode(thrower: Combatant, at: Vector3)
	local blast = Instance.new("Explosion")
	blast.Position = at
	blast.BlastRadius = G.Frag.radius
	blast.BlastPressure = 0 -- visual only; damage is computed below
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = folder
	local boom = Instance.new("Sound")
	boom.SoundId = Config.Sounds.Explosion
	boom.Volume = 1
	boom.RollOffMaxDistance = 300
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = at
	anchor.Parent = workspace.Terrain
	boom.Parent = anchor
	boom:Play()
	task.delay(4, anchor.Destroy, anchor)
	if not Combat.isLive() then
		return
	end
	for _, target in Combatants.all() do
		if target.alive and (target.team ~= thrower.team or target == thrower) then
			local body = (target.root.CFrame * CFrame.new(BODY_OFFSET)).Position
			local dist = (body - at).Magnitude
			if dist <= G.Frag.radius and not workspace:Raycast(at, body - at, Combat.occlusion()) then
				local a = dist / G.Frag.radius
				Combat.damage(target, G.Frag.maxDamage + (G.Frag.minDamage - G.Frag.maxDamage) * a, thrower, "Body")
			end
		end
	end
end

local function smoke(at: Vector3)
	local r = G.Smoke.radius
	table.insert(clouds, { center = at, radius = r, ends = os.clock() + G.Smoke.duration })
	local puffs: { BasePart } = {}
	for i = 0, 6 do
		local angle = i * math.pi / 3
		local offset = if i == 0
			then Vector3.new(0, r * 0.35, 0)
			else Vector3.new(math.cos(angle), 0.15, math.sin(angle)) * r * 0.45
		local puff = Instance.new("Part")
		puff.Shape = Enum.PartType.Ball
		puff.Size = Vector3.one * r * (if i == 0 then 1.3 else 1.1)
		puff.Position = at + offset
		puff.Color = Color3.fromRGB(205, 205, 200)
		puff.Material = Enum.Material.SmoothPlastic
		puff.Transparency = 1
		puff.Anchored, puff.CanCollide, puff.CanQuery, puff.CanTouch, puff.CastShadow = true, false, false, false, false
		puff.Parent = folder
		TweenService:Create(puff, TweenInfo.new(0.8), { Transparency = 0.12 }):Play()
		table.insert(puffs, puff)
	end
	task.delay(G.Smoke.duration - 1.5, function()
		for _, puff in puffs do
			if puff.Parent then
				TweenService:Create(puff, TweenInfo.new(1.5), { Transparency = 1 }):Play()
				task.delay(1.5, puff.Destroy, puff)
			end
		end
	end)
end

local function throw(c: Combatant, kind: Config.GadgetId, dir: Vector3)
	local spec = if kind == "Frag" then G.Frag else G.Smoke
	local grenade = Instance.new("Part")
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.one * 0.8
	grenade.Color = if kind == "Frag" then Color3.fromRGB(70, 80, 50) else Color3.fromRGB(150, 150, 150)
	grenade.Material = Enum.Material.Metal
	grenade.CanQuery, grenade.CanTouch = false, false
	-- Spawn up to 2 studs ahead, but never past a wall the thrower is pressed against.
	local eye = Combat.headPosition(c)
	local blocked = workspace:Raycast(eye, dir * 2.5, Combat.occlusion())
	grenade.Position = if blocked then blocked.Position - dir * 0.6 else eye + dir * 2
	grenade.Parent = folder
	grenade.AssemblyLinearVelocity = dir * spec.throwSpeed + Vector3.new(0, 12, 0)
	task.delay(spec.fuse, function()
		if grenade.Parent then
			local at = grenade.Position
			grenade:Destroy()
			if kind == "Frag" then
				explode(c, at)
			else
				smoke(at)
			end
		end
	end)
end

-- Uses the combatant's gadget. `dir` is where to throw (ignored by the med kit).
function Gadgets.use(c: Combatant, dir: Vector3)
	local kind = c.gadget
	if not kind or not c.alive or not Combat.isLive() or c.gadgetLeft <= 0 or c.healingUntil > 0 then
		return
	end
	if kind == "Medkit" then
		if c.humanoid.Health >= c.humanoid.MaxHealth then
			return
		end
		c.reloadToken += 1 -- healing cancels a reload; you can't shoot while it runs
		c.reloading = false
		c.healingUntil = os.clock() + G.Medkit.channel
		local ends = c.healingUntil
		task.delay(G.Medkit.channel, function()
			if c.alive and c.healingUntil == ends then
				c.healingUntil = 0
				c.humanoid.Health = math.min(c.humanoid.MaxHealth, c.humanoid.Health + G.Medkit.heal)
				Combatants.sync(c)
			end
		end)
	else
		if c.shieldUntil > 0 then
			Combat.dropShield(c)
		end
		throw(c, kind, dir)
	end
	c.gadgetLeft -= 1
	Combatants.sync(c)
end

-- New round: clear grenades in flight and clouds.
function Gadgets.reset()
	table.clear(clouds)
	folder:ClearAllChildren()
end

function Gadgets.bind()
	Net.Gadget.OnServerEvent:Connect(function(player, dir)
		local c = Combatants.byPlayer(player)
		if not c or not Net.allow(player, "Gadget", 2, 2) then
			return
		end
		if not Net.isDirection(dir) then
			AntiCheat.flag(c, "malformed Gadget payload")
			return
		end
		Gadgets.use(c, dir)
	end)
end

return Gadgets
