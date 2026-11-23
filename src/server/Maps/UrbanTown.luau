--!strict
-- Urban Training Town: a fake town for raid practice. A main street runs west to east between the spawn
-- bunkers, a cross street runs north to south through the tower plaza, and four two-story houses, two
-- pocket parks, parked cars, and street clutter give cover. Every piece is point-symmetric.
local MapKit = require(script.Parent.MapKit)

local HALF_X, HALF_Z = 125, 85
local C = MapKit.Colors
local PAINT = Color3.fromRGB(235, 235, 228)
local CONCRETE_GREY = Color3.fromRGB(140, 140, 138)
local BRICK_RED = Color3.fromRGB(150, 62, 48)
local BEIGE = Color3.fromRGB(214, 196, 160)
local PALE_BLUE = Color3.fromRGB(150, 180, 205)
local HOUSE_GREY = Color3.fromRGB(128, 128, 130)
local GLASS = Color3.fromRGB(150, 175, 185)
local LEAVES = Color3.fromRGB(70, 120, 55)

return function(origin: Vector3): MapKit.MapInfo
	local kit = MapKit.new("UrbanTown", origin)

	kit:fill(CFrame.new(0, -6, 0), Vector3.new(420, 12, 320), Enum.Material.Pavement)
	-- Sidewalks go down before both streets so neither sidewalk cuts across the other street.
	local streetX, streetZ = 2 * HALF_X + 12, 2 * HALF_Z + 12
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(streetX, 2, 32), Enum.Material.Concrete)
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(32, 2, streetZ), Enum.Material.Concrete)
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(streetX, 2, 16), Enum.Material.Asphalt)
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(16, 2, streetZ), Enum.Material.Asphalt)
	kit:patch(Vector3.zero, 18, Enum.Material.Concrete)
	-- Brick berm around the edge so the boundary reads as a town wall, not an invisible cliff.
	for _, s in
		{
			{ 0, HALF_Z + 6, 280, 12 },
			{ 0, -HALF_Z - 6, 280, 12 },
			{ HALF_X + 6, 0, 12, 200 },
			{ -HALF_X - 6, 0, 12, 200 },
		}
	do
		kit:fill(CFrame.new(s[1], 3, s[2]), Vector3.new(s[3], 6, s[4]), Enum.Material.Brick)
	end
	-- Pocket parks, one per half. The grass runs deep so the dip walls are grass, not pavement.
	for _, s in { 1, -1 } do
		kit:fill(CFrame.new(s * -80, -4, s * -52), Vector3.new(48, 8, 48), Enum.Material.Grass)
		kit:hill(s * -92, s * -40, 4.5, Enum.Material.Grass)
		kit:hill(s * -68, s * -66, 4, Enum.Material.Grass)
		kit:dip(s * -72, s * -42, Enum.Material.Mud)
	end

	-- Painted lines: dashed center lines, solid edge lines, and crosswalks just outside the plaza.
	local function paint(size: Vector3, x: number, z: number)
		kit:part(size, CFrame.new(x, 0.05, z), PAINT, Enum.Material.SmoothPlastic)
	end
	for _, s in { 1, -1 } do
		for d = 28, 88, 12 do
			paint(Vector3.new(6, 0.1, 0.4), s * d, 0)
		end
		for d = 28, 76, 12 do
			paint(Vector3.new(0.4, 0.1, 6), 0, s * d)
		end
		for _, e in { 1, -1 } do
			paint(Vector3.new(HALF_X - 18, 0.1, 0.3), s * (HALF_X + 18) / 2, e * 7.5)
			paint(Vector3.new(0.3, 0.1, HALF_Z - 18), e * 7.5, s * (HALF_Z + 18) / 2)
		end
		for t = -6, 6, 3 do
			paint(Vector3.new(4, 0.1, 1.5), s * 22, t)
			paint(Vector3.new(1.5, 0.1, 4), t, s * 22)
		end
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

	kit:tower(CFrame.new(0, 0, 0), CONCRETE_GREY)
	kit:office(CFrame.new(-60, 0, 34), BRICK_RED, C.DarkConcrete)
	kit:office(CFrame.new(60, 0, -34) * CFrame.Angles(0, math.pi, 0), BEIGE, C.DarkConcrete)
	kit:office(CFrame.new(-30, 0, -38), PALE_BLUE, C.DarkConcrete)
	kit:office(CFrame.new(30, 0, 38) * CFrame.Angles(0, math.pi, 0), HOUSE_GREY, C.DarkConcrete)

	-- A parked car: body-high cover with a taller cabin.
	local function car(cf: CFrame, color: Color3)
		kit:part(Vector3.new(12, 2.6, 5.6), cf * CFrame.new(0, 2.3, 0), color, Enum.Material.Metal)
		local cabin = Color3.fromRGB(45, 55, 65)
		kit:part(Vector3.new(6.5, 2.2, 5), cf * CFrame.new(-0.5, 4.7, 0), cabin, Enum.Material.Glass)
		for _, x in { -3.8, 3.8 } do
			for _, z in { -2.6, 2.6 } do
				kit:part(
					Vector3.new(1, 2.6, 2.6),
					cf * CFrame.new(x, 1.3, z) * CFrame.Angles(0, math.pi / 2, 0),
					Color3.fromRGB(30, 30, 30),
					Enum.Material.SmoothPlastic,
					"Cylinder"
				)
			end
		end
	end

	-- A bus shelter facing the street on its local -z side, open at the front and on one end.
	local function busStop(cf: CFrame)
		kit:part(Vector3.new(10, 7, 0.4), cf * CFrame.new(0, 3.5, 1.8), GLASS, Enum.Material.Glass)
		kit:part(Vector3.new(0.4, 6.5, 3.6), cf * CFrame.new(-4.8, 3.25, 0), GLASS, Enum.Material.Glass)
		for _, x in { -4.8, 4.8 } do
			kit:part(Vector3.new(0.4, 7.5, 0.4), cf * CFrame.new(x, 3.75, -1.8), C.DarkConcrete, Enum.Material.Metal)
		end
		kit:part(Vector3.new(10.6, 0.4, 4.6), cf * CFrame.new(0, 7.7, 0), C.DarkConcrete, Enum.Material.Metal)
		kit:part(Vector3.new(7, 2, 1.4), cf * CFrame.new(0.5, 1, 1), C.Wood, Enum.Material.WoodPlanks)
		kit:sign(cf * CFrame.new(0, 9.9, 0), "BUS STOP", Color3.fromRGB(30, 90, 160), 8)
	end

	local function dumpster(cf: CFrame)
		kit:part(Vector3.new(6, 4.5, 3.5), cf * CFrame.new(0, 2.25, 0), Color3.fromRGB(40, 90, 55), Enum.Material.Metal)
		local lid = Color3.fromRGB(30, 60, 40)
		kit:part(Vector3.new(6.3, 0.3, 3.8), cf * CFrame.new(0, 4.65, 0), lid, Enum.Material.Metal)
	end

	-- Body-high garden wall, same height as sandbags.
	local function lowWall(cf: CFrame, length: number)
		kit:part(Vector3.new(length, 3.5, 1), cf * CFrame.new(0, 1.75, 0), BRICK_RED, Enum.Material.Brick)
	end

	-- Street cover, point-symmetric so neither side's half is better.
	for _, s in { 1, -1 } do
		local function at(x: number, z: number, yaw: number?): CFrame
			return CFrame.new(s * x, 0, s * z) * CFrame.Angles(0, (yaw or 0) + (if s < 0 then math.pi else 0), 0)
		end
		car(at(-52, 4.5), if s > 0 then Color3.fromRGB(170, 40, 35) else Color3.fromRGB(40, 80, 150))
		busStop(at(-36, 12))
		-- Garden walls in front of each house, with a 6-stud gap lined up with the front door.
		lowWall(at(-68, 20), 10)
		lowWall(at(-52, 20), 10)
		lowWall(at(-38, -22), 10)
		lowWall(at(-22, -22), 10)
		lowWall(at(-80, -22), 18)
		dumpster(at(-84, 24))
		dumpster(at(-48, -28, math.pi / 2))
		kit:crates(at(-104, 40))
		kit:crates(at(-26, 60))
		kit:barrier(at(-80, 4, math.pi / 2), 8)
		kit:barrier(at(-60, 62), 12)
		kit:barrier(at(-4, 50), 9)
		kit:sandbags(at(-62, -4.5, math.pi / 2), 7)
		kit:sandbags(at(-20, -4.5, math.pi / 2), 7)
		kit:sandbags(at(5, 28), 7)
	end

	kit:boundary(HALF_X, HALF_Z)
	kit:clearUnderBuildings(Enum.Material.Asphalt)

	-- Trees and planters go in after clearing so the park grass and plaza concrete stay under them.
	local function tree(x: number, z: number, base: number)
		kit:part(
			Vector3.new(7, 1.6, 1.6),
			CFrame.new(x, base + 3.5, z) * CFrame.Angles(0, 0, math.pi / 2),
			C.Wood,
			Enum.Material.Wood,
			"Cylinder"
		)
		kit:part(Vector3.new(8, 8, 8), CFrame.new(x, base + 9, z), LEAVES, Enum.Material.Grass, "Ball")
	end
	for _, x in { -12, 12 } do
		for _, z in { -12, 12 } do
			kit:part(Vector3.new(4, 2, 4), CFrame.new(x, 1, z), BRICK_RED, Enum.Material.Brick)
			tree(x, z, 2)
		end
	end
	for _, s in { 1, -1 } do
		tree(s * -92, s * -66, 0)
		tree(s * -62, s * -34, 0)
	end

	local spawns = { A = {}, B = {} } :: { A: { CFrame }, B: { CFrame } }
	for i, z in { -4, 4 } do
		spawns.A[i] = CFrame.lookAt(Vector3.new(-106, 3.5, z), Vector3.new(0, 3.5, z))
		spawns.B[i] = CFrame.lookAt(Vector3.new(106, 3.5, z), Vector3.new(0, 3.5, z))
	end
	local waypoints = {
		Vector3.new(-23, 3, -5),
		Vector3.new(23, 3, 5),
		Vector3.new(-60, 3, 23),
		Vector3.new(60, 3, -23),
		Vector3.new(-60, 3, 34),
		Vector3.new(60, 3, -34),
		Vector3.new(-30, 3, -38),
		Vector3.new(30, 3, 38),
		Vector3.new(-52, 3, 10),
		Vector3.new(52, 3, -10),
		Vector3.new(-80, 3, -48),
		Vector3.new(80, 3, 48),
		Vector3.new(-4, 3, 46),
		Vector3.new(4, 3, -46),
		Vector3.new(-77, 3, 4),
		Vector3.new(77, 3, -4),
		Vector3.new(-22, 3, 66),
		Vector3.new(22, 3, -66),
	}
	return kit:info("UrbanTown", "Urban Training Town", spawns, waypoints, HALF_X, HALF_Z)
end
