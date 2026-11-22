--!strict
-- Drop-ins: every round each team arrives by one of four rides, scripted on the server for the
-- length of the loadout pick. Riders stay anchored the whole time (they can't act) and end exactly on
-- their spawn points; the spawn shield starts when the round goes live, at landing.
--   Truck / ArmoredCar: drive in from outside the arena, park behind the spawn bunker, riders vault in.
--   Helicopter: flies in, hovers over the spawn, riders fast-rope down from the side doors.
--   Parachute: riders drift down from high behind the spawn under team canopies.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combatants = require(script.Parent.Combatants)
local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(script.Parent.Vehicles)

export type Group = { team: Config.TeamId, spawns: { CFrame }, riders: { Combatants.Combatant } }

local Drop = {}

Drop.KINDS = { "Helicopter", "Truck", "Parachute", "ArmoredCar" }

local UP = Vector3.yAxis
local HIP = 3.5 -- spawn CFrames sit this far above the ground

local function easeOut(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function phase(t: number, from: number, to: number): number
	return math.clamp((t - from) / (to - from), 0, 1)
end

-- Rider path for one group: returns, for a moment t in 0..1 of the ride, the vehicle pivot (if any)
-- and each rider's root CFrame; plus a cleanup.
type Track = { step: (t: number) -> (), finish: () -> () }

local function ground(kind: string, g: Group, folder: Instance): Track
	local ride = Vehicles.build(kind, g.team)
	ride.model.Parent = folder
	local base = g.spawns[1]
	local look = (base.LookVector * Vector3.new(1, 0, 1)).Unit
	local floor = base.Position - UP * HIP
	local from, to = floor - look * 110, floor - look * 24
	local parked: { CFrame } = {}
	return {
		step = function(t)
			local at = from:Lerp(to, easeOut(phase(t, 0, 0.62)))
			local pivot = CFrame.lookAt(at, at + look)
			ride.model:PivotTo(pivot)
			for i, c in g.riders do
				local seat = pivot * (ride.seats[i] or ride.seats[1])
				local land = g.spawns[i] or base
				if t < 0.7 then
					c.root.CFrame = seat
					parked[i] = seat
				else
					-- Vault over the bunker wall in an arc onto the spawn point.
					local v = easeOut(phase(t, 0.7, 0.92))
					local p = (parked[i] or seat).Position:Lerp(land.Position, v) + UP * (14 * math.sin(v * math.pi))
					c.root.CFrame = CFrame.lookAt(p, p + land.LookVector)
				end
			end
		end,
		finish = function()
			ride.model:Destroy()
		end,
	}
end

local function helicopter(g: Group, folder: Instance): Track
	local ride = Vehicles.build("Helicopter", g.team)
	ride.model.Parent = folder
	local look = (g.spawns[1].LookVector * Vector3.new(1, 0, 1)).Unit
	local center = Vector3.zero
	for _, s in g.spawns do
		center += s.Position
	end
	center /= #g.spawns
	local hover = center - UP * HIP + UP * 24
	local from = hover - look * 150 + UP * 40
	local ropes: { Part } = {}
	for i in g.riders do
		local rope = Instance.new("Part")
		rope.Anchored, rope.CanCollide, rope.CanQuery, rope.CanTouch = true, false, false, false
		rope.Color = Color3.fromRGB(70, 60, 45)
		rope.Material = Enum.Material.Fabric
		rope.Transparency = 1
		rope.Parent = folder
		ropes[i] = rope
	end
	return {
		step = function(t)
			local at = from:Lerp(hover, easeOut(phase(t, 0, 0.5)))
			local pivot = CFrame.lookAt(at, at + look)
			ride.model:PivotTo(pivot)
			if ride.spin then
				ride.spin.CFrame *= CFrame.Angles(0, 0.6, 0)
			end
			for i, c in g.riders do
				local seat = pivot * (ride.seats[i] or ride.seats[1])
				local land = g.spawns[i] or g.spawns[1]
				local anchor = pivot * ((ride.door and ride.door[i]) or ride.seats[i] or ride.seats[1])
				local r = phase(t, 0.6, 0.9)
				if r <= 0 then
					c.root.CFrame = seat
					continue
				end
				-- Fast-rope: slide from the door straight down the rope to the spawn point.
				local top = anchor.Position
				local p = Vector3.new(land.Position.X, top.Y, land.Position.Z):Lerp(land.Position, r)
				c.root.CFrame = CFrame.lookAt(p, p + land.LookVector)
				local rope = ropes[i]
				local length = math.max(top.Y - land.Position.Y + HIP, 0.5)
				rope.Size = Vector3.new(0.25, length, 0.25)
				rope.CFrame = CFrame.new(Vector3.new(land.Position.X, top.Y - length / 2, land.Position.Z))
				rope.Transparency = if r < 1 then 0 else 1
			end
		end,
		finish = function()
			ride.model:Destroy()
			for _, rope in ropes do
				rope:Destroy()
			end
		end,
	}
end

local function parachute(g: Group, folder: Instance): Track
	local canopies: { Model } = {}
	for i in g.riders do
		local canopy = Vehicles.parachute(g.team)
		canopy.Parent = folder
		canopies[i] = canopy
	end
	local look = (g.spawns[1].LookVector * Vector3.new(1, 0, 1)).Unit
	return {
		step = function(t)
			for i, c in g.riders do
				local land = g.spawns[i] or g.spawns[1]
				local start = land.Position + UP * 80 - look * 35
				local d = phase(t, 0, 0.9)
				local sway = Vector3.new(math.sin(t * 9 + i) * 1.5, 0, math.cos(t * 7 + i) * 1.5) * (1 - d)
				local p = start:Lerp(land.Position, d) + sway
				c.root.CFrame = CFrame.lookAt(p, p + land.LookVector)
				local canopy = canopies[i]
				if d < 1 then
					canopy:PivotTo(c.root.CFrame)
				elseif canopy.Parent then
					canopy:Destroy() -- landed: the canopy is cut away
				end
			end
		end,
		finish = function()
			for _, canopy in canopies do
				canopy:Destroy()
			end
		end,
	}
end

-- Runs one ride of `kind` for every group, taking `seconds`; returns with every rider anchored on
-- their spawn point. `folder` holds the ride's models and is the caller's to clear.
function Drop.run(kind: string, groups: { Group }, seconds: number, folder: Instance)
	local tracks: { Track } = {}
	for _, g in groups do
		if #g.riders > 0 then
			table.insert(
				tracks,
				if kind == "Helicopter"
					then helicopter(g, folder)
					elseif kind == "Parachute" then parachute(g, folder)
					else ground(kind, g, folder)
			)
		end
	end
	local start = os.clock()
	while true do
		local t = (os.clock() - start) / seconds
		for _, track in tracks do
			track.step(math.min(t, 1))
		end
		if t >= 1 then
			break
		end
		task.wait()
	end
	for _, track in tracks do
		track.finish()
	end
	for _, g in groups do
		for i, c in g.riders do
			if c.root.Parent then
				c.root.CFrame = g.spawns[i] or g.spawns[1]
			end
		end
	end
end

return Drop
