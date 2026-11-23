--!strict
-- Desert Outpost: sand with sandstone flats, dunes and rocky dips, spawn bunkers on side A (west) and
-- side B (east), a central watchtower, two sandstone two-story buildings, and a shipping-container yard.
local MapKit = require(script.Parent.MapKit)

local HALF_X, HALF_Z = 125, 85
local C = MapKit.Colors
local WALL = Color3.fromRGB(205, 185, 145)
local TRIM = Color3.fromRGB(140, 118, 84)
local TAN = Color3.fromRGB(176, 150, 104)
local RUST = Color3.fromRGB(150, 70, 50)
local BLUE = Color3.fromRGB(80, 105, 130)
local OLIVE = Color3.fromRGB(105, 110, 75)
local TANK = Color3.fromRGB(196, 190, 176)
local DRUM = Color3.fromRGB(160, 60, 45)

return function(origin: Vector3): MapKit.MapInfo
	local kit = MapKit.new("DesertOutpost", origin)

	kit:fill(CFrame.new(0, -6, 0), Vector3.new(420, 12, 320), Enum.Material.Sand)
	local seed = Random.new(1991)
	for _ = 1, 30 do
		local at = Vector3.new(seed:NextNumber(-HALF_X, HALF_X), 0, seed:NextNumber(-HALF_Z, HALF_Z))
		kit:patch(at, seed:NextNumber(5, 12), Enum.Material.Sandstone)
	end
	kit:patch(Vector3.zero, 13, Enum.Material.Sandstone)
	-- Sandstone ridge around the edge so the boundary reads as a wall, not an invisible cliff.
	for _, s in
		{
			{ 0, HALF_Z + 6, 280, 12 },
			{ 0, -HALF_Z - 6, 280, 12 },
			{ HALF_X + 6, 0, 12, 200 },
			{ -HALF_X - 6, 0, 12, 200 },
		}
	do
		kit:fill(CFrame.new(s[1], 3, s[2]), Vector3.new(s[3], 6, s[4]), Enum.Material.Sandstone)
	end
	local dunes =
		{ { -60, 62, 5 }, { 60, -62, 5 }, { -40, -40, 4.5 }, { 40, 40, 4.5 }, { -100, -55, 6 }, { 100, 55, 6 } }
	for _, h in dunes do
		kit:hill(h[1], h[2], h[3], Enum.Material.Sand)
	end
	for _, d in { { -70, -30 }, { 70, 30 }, { -28, -12 }, { 28, 12 } } do
		kit:dip(d[1], d[2], Enum.Material.Rock)
	end

	-- Spawn bunkers: a pad, a back wall, and two side walls.
	for _, side in { -1, 1 } do
		local base = CFrame.new(side * 108, 0, 0) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0)
		kit:part(Vector3.new(26, 0.4, 14), base * CFrame.new(0, 0.2, 0), TRIM)
		kit:part(Vector3.new(26, 10, 1.5), base * CFrame.new(0, 5, 7.5), WALL, Enum.Material.Sandstone)
		kit:part(Vector3.new(1.5, 10, 8), base * CFrame.new(-12.5, 5, 3.5), WALL, Enum.Material.Sandstone)
		kit:part(Vector3.new(1.5, 10, 8), base * CFrame.new(12.5, 5, 3.5), WALL, Enum.Material.Sandstone)
		kit:sign(
			base * CFrame.new(0, 12, 7.5) * CFrame.Angles(0, math.pi, 0),
			side < 0 and "SIDE A" or "SIDE B",
			C.Olive
		)
		kit:sandbags(base * CFrame.new(-7, 0, -6), 8)
		kit:sandbags(base * CFrame.new(7, 0, -6), 8)
	end

	kit:tower(CFrame.new(0, 0, 0), TAN)

	-- Shipping container, 8 x 8.5 x 20 with its long side along local z. Open ones are walk-through
	-- tunnels (7 studs wide inside); closed ones get a darker door panel on the +z end.
	local function container(cf: CFrame, color: Color3, open: boolean?)
		if open then
			for _, x in { -3.75, 3.75 } do
				kit:part(Vector3.new(0.5, 8.5, 20), cf * CFrame.new(x, 4.25, 0), color, Enum.Material.Metal)
			end
			kit:part(Vector3.new(8, 0.5, 20), cf * CFrame.new(0, 8.25, 0), color, Enum.Material.Metal)
			kit:part(Vector3.new(7, 0.3, 20), cf * CFrame.new(0, 0.15, 0), TRIM, Enum.Material.DiamondPlate)
		else
			kit:part(Vector3.new(8, 8.5, 20), cf * CFrame.new(0, 4.25, 0), color, Enum.Material.Metal)
			local door = color:Lerp(Color3.new(), 0.25)
			kit:part(Vector3.new(7, 7.5, 0.2), cf * CFrame.new(0, 4.25, 10.1), door, Enum.Material.Metal)
		end
	end

	-- Octagon of sandbags with one side left open as the way in (the open side faces local -z).
	local function ring(cf: CFrame)
		for i = 1, 7 do
			kit:sandbags(cf * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, 0, -5), 4.8)
		end
	end

	-- Horizontal fuel tank on two cradles; the 1-stud gap underneath is too low to crawl through.
	local function tank(cf: CFrame)
		for _, x in { -4.5, 4.5 } do
			kit:part(Vector3.new(1, 2.5, 6), cf * CFrame.new(x, 1.25, 0), C.DarkConcrete)
		end
		kit:part(Vector3.new(14, 7, 7), cf * CFrame.new(0, 4.5, 0), TANK, Enum.Material.Metal, "Cylinder")
		kit:part(Vector3.new(1, 7.3, 7.3), cf * CFrame.new(0, 4.5, 0), RUST, Enum.Material.Metal, "Cylinder")
	end

	-- Everything below is point-symmetric (rotated 180 degrees about the tower) so neither half is better.
	for _, s in { 1, -1 } do
		local function at(x: number, z: number, yaw: number?): CFrame
			return CFrame.new(s * x, 0, s * z) * CFrame.Angles(0, (yaw or 0) + (s < 0 and math.pi or 0), 0)
		end

		kit:office(at(-50, 34), WALL, TRIM)

		container(at(-36, 12, math.pi / 2), BLUE, true)
		container(at(-82, -45), RUST)
		container(at(-20, 48, 0.3), TAN)
		container(at(-96, 50, math.pi / 2), BLUE)
		-- Stacked pair with a ladder up the field-facing side and sandbags on the roof.
		local stack = at(-62, -58, math.pi / 2)
		container(stack, OLIVE)
		container(CFrame.new(0, 8.5, 0) * stack, RUST)
		kit:part(Vector3.new(2, 18, 2), CFrame.new(s * -66, 9, s * -53), C.DarkConcrete, Enum.Material.Metal, "Truss")
		kit:sandbags(CFrame.new(0, 17, 0) * at(-54, -58, math.pi / 2), 7)

		tank(at(-74, 22))
		for _, d in { { -86, 27 }, { -88.5, 23 }, { -85.5, 20 } } do
			local upright = at(d[1], d[2]) * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			kit:part(Vector3.new(4, 3, 3), upright, DRUM, Enum.Material.Metal, "Cylinder")
		end

		ring(at(-50, -20, math.pi / 2))
		ring(at(-14, -34, math.pi / 2))
		kit:barrier(at(-84, -16, math.pi / 2), 12)
		kit:barrier(at(-16, 16), 10)
		kit:sandbags(at(-60, 4, 0.3), 9)
		kit:crates(at(-30, -62))
		kit:crates(at(-100, -28, 0.2))
	end

	kit:boundary(HALF_X, HALF_Z)
	kit:clearUnderBuildings(Enum.Material.Sandstone)

	local spawns = { A = {}, B = {} } :: { A: { CFrame }, B: { CFrame } }
	for i, z in { -4, 4 } do
		spawns.A[i] = CFrame.lookAt(Vector3.new(-106, 3.5, z), Vector3.new(0, 3.5, z))
		spawns.B[i] = CFrame.lookAt(Vector3.new(106, 3.5, z), Vector3.new(0, 3.5, z))
	end
	local waypoints = {
		Vector3.new(0, 3, 9),
		Vector3.new(0, 3, -9),
		Vector3.new(-36, 3, 20),
		Vector3.new(36, 3, -20),
		Vector3.new(-50, 3, 22),
		Vector3.new(50, 3, -22),
		Vector3.new(-74, 3, 14),
		Vector3.new(74, 3, -14),
		Vector3.new(-50, 3, -20),
		Vector3.new(50, 3, 20),
		Vector3.new(-14, 3, -34),
		Vector3.new(14, 3, 34),
		Vector3.new(-88, 3, -16),
		Vector3.new(88, 3, 16),
		Vector3.new(-28, 3, 48),
		Vector3.new(28, 3, -48),
		Vector3.new(-36, 3, -62),
		Vector3.new(36, 3, 62),
		Vector3.new(-82, 3, -30),
		Vector3.new(82, 3, 30),
	}
	return kit:info("DesertOutpost", "Desert Outpost", spawns, waypoints, HALF_X, HALF_Z)
end
