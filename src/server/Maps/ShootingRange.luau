--!strict
-- The Shooting Range: grass with hills and dips, spawn bunkers on side A (west) and side B (east),
-- a central control tower, two two-story range offices, firing lanes with targets, and cover.
local MapKit = require(script.Parent.MapKit)

local HALF_X, HALF_Z = 125, 85
local C = MapKit.Colors

return function(origin: Vector3): MapKit.MapInfo
	local kit = MapKit.new("ShootingRange", origin)

	kit:fill(CFrame.new(0, -6, 0), Vector3.new(420, 12, 320), Enum.Material.Grass)
	local seed = Random.new(1945)
	for _ = 1, 34 do
		local at = Vector3.new(seed:NextNumber(-HALF_X, HALF_X), 0, seed:NextNumber(-HALF_Z, HALF_Z))
		kit:patch(at, seed:NextNumber(5, 13), Enum.Material.LeafyGrass)
	end
	-- Worn dirt paths from each spawn toward the tower, and a ring around the tower base.
	for _, side in { -1, 1 } do
		kit:fill(
			CFrame.new(side * 62, -1, 0) * CFrame.Angles(0, side * 0.05, 0),
			Vector3.new(80, 2, 4.5),
			Enum.Material.Ground
		)
	end
	kit:patch(Vector3.zero, 13, Enum.Material.Ground)
	-- Sand berm around the edge so the boundary reads as a wall, not an invisible cliff.
	for _, s in
		{
			{ 0, HALF_Z + 6, 280, 12 },
			{ 0, -HALF_Z - 6, 280, 12 },
			{ HALF_X + 6, 0, 12, 200 },
			{ -HALF_X - 6, 0, 12, 200 },
		}
	do
		kit:fill(CFrame.new(s[1], 3, s[2]), Vector3.new(s[3], 6, s[4]), Enum.Material.Sand)
	end
	for _, h in { { -40, 32 }, { 40, -32 }, { -18, -40 }, { 18, 40 }, { -82, -55 }, { 82, 55 } } do
		kit:hill(h[1], h[2], 4.5, Enum.Material.Grass)
	end
	for _, d in { { -70, 50 }, { 70, -50 }, { -22, 8 }, { 22, -8 } } do
		kit:dip(d[1], d[2], Enum.Material.Mud)
	end

	-- Spawn bunkers: a pad, a back wall, and two side walls.
	for _, side in { -1, 1 } do
		local base = CFrame.new(side * 108, 0, 0) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0)
		kit:part(Vector3.new(26, 0.4, 14), base * CFrame.new(0, 0.2, 0), C.DarkConcrete)
		kit:part(Vector3.new(26, 10, 1.5), base * CFrame.new(0, 5, 7.5), C.Concrete)
		kit:part(Vector3.new(1.5, 10, 8), base * CFrame.new(-12.5, 5, 3.5), C.Concrete)
		kit:part(Vector3.new(1.5, 10, 8), base * CFrame.new(12.5, 5, 3.5), C.Concrete)
		kit:sign(
			base * CFrame.new(0, 12, 7.5) * CFrame.Angles(0, math.pi, 0),
			side < 0 and "SIDE A" or "SIDE B",
			C.Olive
		)
		kit:sandbags(base * CFrame.new(-7, 0, -6), 8)
		kit:sandbags(base * CFrame.new(7, 0, -6), 8)
	end

	kit:tower(CFrame.new(0, 0, 0))
	kit:office(CFrame.new(-55, 0, 30))
	kit:office(CFrame.new(55, 0, -30) * CFrame.Angles(0, math.pi, 0))

	-- Firing lanes along the south edge: lane dividers are body-high cover, targets downrange.
	for x = -36, 36, 12 do
		kit:sandbags(CFrame.new(x, 0, -58) * CFrame.Angles(0, math.pi / 2, 0), 12)
		kit:target(CFrame.new(x + 6, 0, -76))
	end
	kit:part(Vector3.new(80, 3, 1), CFrame.new(0, 1.5, -51.5), C.Wood, Enum.Material.WoodPlanks)
	kit:crates(CFrame.new(-20, 0, 62))
	kit:crates(CFrame.new(14, 0, 66) * CFrame.Angles(0, 0.4, 0))
	kit:barrier(CFrame.new(0, 0, 54), 14)

	-- Mid-field cover, point-symmetric so neither side's half is better.
	for _, s in { 1, -1 } do
		local function at(x: number, z: number, yaw: number?): CFrame
			return CFrame.new(s * x, 0, s * z) * CFrame.Angles(0, yaw or 0, 0)
		end
		kit:sandbags(at(-78, 16, math.pi / 2), 10)
		kit:barrier(at(-78, -20, math.pi / 2), 12)
		kit:sandbags(at(-30, -14), 10)
		kit:barrier(at(-16, 16), 10)
		kit:crates(at(-92, 40))
		kit:sandbags(at(-56, -6, 0.3), 9)
	end

	kit:boundary(HALF_X, HALF_Z)
	kit:clearUnderBuildings(Enum.Material.Ground)

	local spawns = { A = {}, B = {} } :: { A: { CFrame }, B: { CFrame } }
	for i, z in { -4, 4 } do
		spawns.A[i] = CFrame.lookAt(Vector3.new(-106, 3.5, z), Vector3.new(0, 3.5, z))
		spawns.B[i] = CFrame.lookAt(Vector3.new(106, 3.5, z), Vector3.new(0, 3.5, z))
	end
	local waypoints = {
		Vector3.new(0, 3, 9),
		Vector3.new(0, 3, -9),
		Vector3.new(-55, 3, 18),
		Vector3.new(55, 3, -18),
		Vector3.new(-55, 3, 42),
		Vector3.new(55, 3, -42),
		Vector3.new(-30, 3, -20),
		Vector3.new(30, 3, 20),
		Vector3.new(-78, 3, 0),
		Vector3.new(78, 3, 0),
		Vector3.new(-24, 3, -54),
		Vector3.new(24, 3, -54),
		Vector3.new(-10, 3, 50),
		Vector3.new(10, 3, 58),
		Vector3.new(-40, 6, 32),
		Vector3.new(40, 6, -32),
	}
	return kit:info("ShootingRange", "Shooting Range", spawns, waypoints, HALF_X, HALF_Z)
end
