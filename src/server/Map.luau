--!strict
-- The Shooting Range, built from code: terrain with hills and dips, spawn bunkers on side A (west)
-- and side B (east), a central control tower, two two-story range offices, firing lanes, cover,
-- invisible boundary walls, and a glass spectator gallery outside the play area.
local Lighting = game:GetService("Lighting")

local Map = {}

export type MapInfo = {
	spawns: { A: { CFrame }, B: { CFrame } },
	boundsMin: Vector3,
	boundsMax: Vector3,
	waypoints: { Vector3 },
	gallery: CFrame,
}

local HALF_X, HALF_Z = 125, 85

local CONCRETE = Color3.fromRGB(165, 160, 150)
local DARK_CONCRETE = Color3.fromRGB(120, 116, 108)
local SANDBAG = Color3.fromRGB(176, 154, 112)
local WOOD = Color3.fromRGB(120, 88, 56)
local OLIVE = Color3.fromRGB(86, 94, 62)

local geometry: Folder

local function part(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?,
	kind: string?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	elseif kind == "Truss" then
		p = Instance.new("TrussPart")
	else
		p = Instance.new("Part")
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or geometry
	return p
end

-- A wall of `length` x `height` along local X, centered on `cf` at its base, with rectangular holes
-- {x0, x1, y0, y1} in wall-local coordinates (x from -length/2, y from 0). Holes must not overlap in x.
local function wall(cf: CFrame, length: number, height: number, holes: { { number } }, color: Color3?)
	local cuts = { -length / 2, length / 2 }
	for _, h in holes do
		table.insert(cuts, h[1])
		table.insert(cuts, h[2])
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local x0, x1 = cuts[i], cuts[i + 1]
		if x1 - x0 > 0.01 then
			local spans = { { 0, height } }
			for _, h in holes do
				if h[1] <= x0 + 0.01 and h[2] >= x1 - 0.01 then
					spans = { { 0, h[3] }, { h[4], height } }
				end
			end
			for _, s in spans do
				if s[2] - s[1] > 0.01 then
					local mid = Vector3.new((x0 + x1) / 2, (s[1] + s[2]) / 2, 0)
					part(Vector3.new(x1 - x0, s[2] - s[1], 1), cf * CFrame.new(mid), color or CONCRETE)
				end
			end
		end
	end
end

local function sandbags(cf: CFrame, length: number)
	part(Vector3.new(length, 3.5, 2), cf * CFrame.new(0, 1.75, 0), SANDBAG, Enum.Material.Sand)
end

local function barrier(cf: CFrame, length: number)
	part(Vector3.new(length, 7, 1.5), cf * CFrame.new(0, 3.5, 0), DARK_CONCRETE)
end

local function crates(cf: CFrame)
	part(Vector3.new(5, 5, 5), cf * CFrame.new(0, 2.5, 0), WOOD, Enum.Material.WoodPlanks)
	part(Vector3.new(5, 5, 5), cf * CFrame.new(5.2, 2.5, 0.6), WOOD, Enum.Material.WoodPlanks)
	part(Vector3.new(4, 4, 4), cf * CFrame.new(2.6, 7, 0.2) * CFrame.Angles(0, 0.3, 0), WOOD, Enum.Material.WoodPlanks)
end

local function sign(cf: CFrame, text: string, color: Color3)
	local board = part(Vector3.new(14, 4, 0.5), cf, color, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
end

-- Two-story range office: 24 x 16, doors on both long sides, windows on every wall, a ramp to
-- the second floor and a roof. `cf` is the ground-level center.
local function office(cf: CFrame)
	local L, W, H = 24, 16, 10
	part(Vector3.new(L, 0.4, W), cf * CFrame.new(0, 0.2, 0), DARK_CONCRETE)
	local door = { -2.5, 2.5, 0, 7 }
	local lowWin = { { -9, -5, 3.5, 6.5 }, { 5, 9, 3.5, 6.5 } }
	local highWin = { { -9, -5, 3.5, 6.5 }, { -2, 2, 3.5, 6.5 }, { 5, 9, 3.5, 6.5 } }
	local function long(z: number, yaw: number)
		local holes = { door }
		for _, w in lowWin do
			table.insert(holes, w)
		end
		wall(cf * CFrame.new(0, 0, z) * CFrame.Angles(0, yaw, 0), L, H, holes)
		wall(cf * CFrame.new(0, H, z) * CFrame.Angles(0, yaw, 0), L, H, highWin)
	end
	long(W / 2, 0)
	long(-W / 2, math.pi)
	for _, x in { L / 2, -L / 2 } do
		local side = cf * CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
		wall(side, W - 1, H, { { -2, 2, 3.5, 6.5 } })
		wall(side * CFrame.new(0, H, 0), W - 1, H, { { -2, 2, 3.5, 6.5 } })
	end
	-- Second floor with a stairwell along the -x end: a ramp rises toward -z onto a landing that is
	-- flush with the floor, so the route upstairs is continuous.
	part(Vector3.new(L - 7, 1, W - 1), cf * CFrame.new(3.5, H + 0.5, 0), CONCRETE)
	part(Vector3.new(7, 1, 3), cf * CFrame.new(-L / 2 + 3.5, H + 0.5, -W / 2 + 2), CONCRETE)
	part(
		Vector3.new(6, H + 1, 11),
		cf * CFrame.new(-L / 2 + 3.5, (H + 1) / 2, 1) * CFrame.Angles(0, math.pi, 0),
		CONCRETE,
		nil,
		nil,
		"Wedge"
	)
	part(Vector3.new(L, 1, W), cf * CFrame.new(0, 2 * H + 0.5, 0), DARK_CONCRETE)
end

local function tower(cf: CFrame)
	local h = 18
	for _, x in { -5, 5 } do
		for _, z in { -5, 5 } do
			part(Vector3.new(1.5, h, 1.5), cf * CFrame.new(x, h / 2, z), OLIVE, Enum.Material.Metal)
		end
	end
	part(Vector3.new(12, 1, 12), cf * CFrame.new(0, h + 0.5, 0), OLIVE, Enum.Material.DiamondPlate)
	-- Railings: full on the z sides, split on the x sides so each ladder arrives through a 3-stud gap.
	local rails = { { 0, 5.75, 12, 0.5 }, { 0, -5.75, 12, 0.5 } }
	for _, x in { 5.75, -5.75 } do
		table.insert(rails, { x, 3.75, 0.5, 4.5 })
		table.insert(rails, { x, -3.75, 0.5, 4.5 })
	end
	for _, s in rails do
		part(Vector3.new(s[3], 2.5, s[4]), cf * CFrame.new(s[1], h + 2.25, s[2]), OLIVE, Enum.Material.Metal)
	end
	-- Ladders facing both spawns.
	for _, x in { -6.75, 6.75 } do
		part(Vector3.new(2, h + 1, 2), cf * CFrame.new(x, (h + 1) / 2, 0), OLIVE, Enum.Material.Metal, nil, "Truss")
	end
	part(Vector3.new(5, 0.5, 5), cf * CFrame.new(0, h + 7, 0), Color3.fromRGB(200, 60, 40), Enum.Material.SmoothPlastic)
	part(Vector3.new(0.4, 6, 0.4), cf * CFrame.new(0, h + 4, 0), OLIVE, Enum.Material.Metal)
end

local function target(cf: CFrame)
	part(Vector3.new(0.4, 5, 0.4), cf * CFrame.new(0, 2.5, 0), WOOD, Enum.Material.Wood)
	local colors =
		{ Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 30), Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 30) }
	for i, color in colors do
		local d = 4.5 - (i - 1) * 1.1
		local ring = part(
			Vector3.new(0.2 + i * 0.05, d, d),
			cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			color,
			Enum.Material.SmoothPlastic
		) :: Part
		ring.Shape = Enum.PartType.Cylinder
	end
end

local function terrain()
	local t = workspace.Terrain
	t:Clear()
	t:FillBlock(CFrame.new(0, -6, 0), Vector3.new(420, 12, 320), Enum.Material.Grass)
	-- Sand berm around the edge so the boundary reads as a wall, not an invisible cliff.
	for _, s in
		{
			{ 0, HALF_Z + 6, 280, 12 },
			{ 0, -HALF_Z - 6, 280, 12 },
			{ HALF_X + 6, 0, 12, 200 },
			{ -HALF_X - 6, 0, 12, 200 },
		}
	do
		t:FillBlock(CFrame.new(s[1], 3, s[2]), Vector3.new(s[3], 6, s[4]), Enum.Material.Sand)
	end
	for _, h in { { -40, 32 }, { 40, -32 }, { -18, -40 }, { 18, 40 }, { -82, -55 }, { 82, 55 } } do
		t:FillBall(Vector3.new(h[1], -7, h[2]), 11.5, Enum.Material.Grass)
	end
	for _, d in { { -70, 50 }, { 70, -50 }, { -22, 8 }, { 22, -8 } } do
		t:FillBall(Vector3.new(d[1], 3.5, d[2]), 7, Enum.Material.Air)
		t:FillBall(Vector3.new(d[1], -5.5, d[2]), 3, Enum.Material.Mud)
	end
end

local function lighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.5
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 130, 125)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 1.2
	atmosphere.Color = Color3.fromRGB(205, 210, 200)
	atmosphere.Decay = Color3.fromRGB(110, 120, 110)
	atmosphere.Parent = Lighting
end

function Map.build(): MapInfo
	geometry = Instance.new("Folder")
	geometry.Name = "ShootingRange"
	geometry.Parent = workspace
	terrain()
	lighting()

	-- Spawn bunkers: a pad, a back wall, and two side walls the drop-in walks out of.
	for _, side in { -1, 1 } do
		local base = CFrame.new(side * 108, 0, 0) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0)
		part(Vector3.new(26, 0.4, 14), base * CFrame.new(0, 0.2, 0), DARK_CONCRETE)
		part(Vector3.new(26, 10, 1.5), base * CFrame.new(0, 5, 7.5), CONCRETE)
		part(Vector3.new(1.5, 10, 8), base * CFrame.new(-12.5, 5, 3.5), CONCRETE)
		part(Vector3.new(1.5, 10, 8), base * CFrame.new(12.5, 5, 3.5), CONCRETE)
		sign(base * CFrame.new(0, 12, 7.5) * CFrame.Angles(0, math.pi, 0), side < 0 and "SIDE A" or "SIDE B", OLIVE)
		sandbags(base * CFrame.new(-7, 0, -6), 8)
		sandbags(base * CFrame.new(7, 0, -6), 8)
	end

	tower(CFrame.new(0, 0, 0))
	office(CFrame.new(-55, 0, 30))
	office(CFrame.new(55, 0, -30) * CFrame.Angles(0, math.pi, 0))

	-- Firing lanes along the south edge: lane dividers are body-high cover, targets downrange.
	for x = -36, 36, 12 do
		sandbags(CFrame.new(x, 0, -58) * CFrame.Angles(0, math.pi / 2, 0), 12)
		target(CFrame.new(x + 6, 0, -76))
	end
	part(Vector3.new(80, 3, 1), CFrame.new(0, 1.5, -51.5), WOOD, Enum.Material.WoodPlanks)
	-- Ammo depot along the north edge.
	crates(CFrame.new(-20, 0, 62))
	crates(CFrame.new(14, 0, 66) * CFrame.Angles(0, 0.4, 0))
	barrier(CFrame.new(0, 0, 54), 14)

	-- Mid-field cover, point-symmetric so neither side's half is better.
	for _, s in { 1, -1 } do
		local function at(x: number, z: number, yaw: number?): CFrame
			return CFrame.new(s * x, 0, s * z) * CFrame.Angles(0, yaw or 0, 0)
		end
		sandbags(at(-78, 16, math.pi / 2), 10)
		barrier(at(-78, -20, math.pi / 2), 12)
		sandbags(at(-30, -14), 10)
		barrier(at(-16, 16), 10)
		crates(at(-92, 40))
		sandbags(at(-56, -6, 0.3), 9)
	end

	-- Boundary: invisible walls and a ceiling the movement check also enforces.
	for _, s in
		{
			{ 0, HALF_Z, HALF_X * 2, 1 },
			{ 0, -HALF_Z, HALF_X * 2, 1 },
			{ HALF_X, 0, 1, HALF_Z * 2 },
			{ -HALF_X, 0, 1, HALF_Z * 2 },
		}
	do
		local w = part(Vector3.new(s[3], 120, s[4]), CFrame.new(s[1], 50, s[2]), Color3.new(), nil)
		w.Transparency = 1
		w.CanQuery = false
	end

	-- Spectator gallery: enclosed glass box north of the field, outside the play area.
	local gallery = CFrame.new(0, 34, HALF_Z + 22)
	part(Vector3.new(40, 1, 14), gallery, CONCRETE)
	for _, g in { { 0, -7, 40, 1 }, { 0, 7, 40, 1 }, { 20, 0, 1, 14 }, { -20, 0, 1, 14 } } do
		local glass = part(
			Vector3.new(g[3], 10, g[4]),
			gallery * CFrame.new(g[1], 5.5, g[2]),
			Color3.fromRGB(180, 210, 230),
			Enum.Material.Glass
		)
		glass.Transparency = 0.7
	end
	part(Vector3.new(40, 1, 14), gallery * CFrame.new(0, 11, 0), CONCRETE)

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

	return {
		spawns = spawns,
		boundsMin = Vector3.new(-HALF_X + 1, -12, -HALF_Z + 1),
		boundsMax = Vector3.new(HALF_X - 1, 60, HALF_Z - 1),
		waypoints = waypoints,
		gallery = gallery * CFrame.new(0, 4, 0),
	}
end

return Map
