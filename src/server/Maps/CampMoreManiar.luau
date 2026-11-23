--!strict
-- Camp More Maniar (a play on Noelle's last name, Moore, and on her being "more Maniar"): the lobby
-- courtyard players walk around between matches. A parade ground with the
-- statue of Joanna and Eddie Moore at its center, the entrance gate behind it, the shop and armory
-- on either side, and the leaderboard. Not an arena: no sides, spawns per team, or waypoints.
local MapKit = require(script.Parent.MapKit)

local HALF_X, HALF_Z = 90, 70
local C = MapKit.Colors
local STONE = Color3.fromRGB(228, 225, 218)
local STONE_SHADE = Color3.fromRGB(198, 194, 186)
local BRONZE = Color3.fromRGB(104, 76, 40)
local GOLD = Color3.fromRGB(240, 205, 110)
local NAVY = Color3.fromRGB(24, 34, 62)
local METAL = Color3.fromRGB(150, 152, 156)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- turns a Cylinder part's X axis vertical

export type LobbyInfo = {
	spawn: CFrame,
	leaderboard: TextLabel,
	range: {
		min: Vector3,
		max: Vector3,
		racks: { CFrame }, -- world CFrame of each rack top
		targets: { CFrame }, -- world CFrame of each lane's dummy, facing the firing line
	},
}

local function boardOf(label: TextLabel): BasePart
	return label:FindFirstAncestorWhichIsA("BasePart") :: BasePart
end

return function(origin: Vector3): LobbyInfo
	local kit = MapKit.new("CampMoreManiar", origin)

	-- Ground: grass, a cobblestone border around the concrete parade ground, cobblestone paths to the
	-- gate and to the shop and armory doors.
	kit:fill(CFrame.new(0, -6, 0), Vector3.new(200, 12, 160), Enum.Material.Grass)
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(88, 2, 68), Enum.Material.Cobblestone)
	kit:fill(CFrame.new(0, -1, 0), Vector3.new(80, 2, 60), Enum.Material.Concrete)
	kit:fill(CFrame.new(0, -1, -49), Vector3.new(12, 2, 38), Enum.Material.Cobblestone)
	for _, side in { -1, 1 } do
		kit:fill(CFrame.new(side * 46, -1, 0), Vector3.new(12, 2, 28), Enum.Material.Cobblestone)
	end

	-- Low perimeter wall (the invisible boundary sits just outside it), open at the north gate.
	kit:wall(CFrame.new(0, 0, -68), 176, 4, { { -9, 9, 0, 4 } }, C.DarkConcrete)
	kit:wall(CFrame.new(0, 0, 68), 176, 4, {}, C.DarkConcrete)
	for _, side in { -1, 1 } do
		kit:wall(CFrame.new(side * 88, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 137, 4, {}, C.DarkConcrete)
	end

	-- Entrance gate: posts, a crossbeam carrying the CAMP MORE MANIAR sign, a boom barrier and a guard booth.
	for _, side in { -1, 1 } do
		kit:part(Vector3.new(3, 18, 3), CFrame.new(side * 10.5, 9, -68), C.DarkConcrete)
		kit:part(Vector3.new(3.6, 0.8, 3.6), CFrame.new(side * 10.5, 18.4, -68), C.Concrete)
	end
	kit:part(Vector3.new(24, 2.5, 2.4), CFrame.new(0, 15, -68), C.Olive, Enum.Material.Metal)
	local gateSignAt = CFrame.lookAt(Vector3.new(0, 15, -66.55), Vector3.new(0, 15, 0))
	local campSign = kit:sign(gateSignAt, "CAMP MORE MANIAR", C.Olive, 20)
	campSign.TextColor3 = GOLD
	boardOf(campSign).Size = Vector3.new(20, 4.5, 0.5)
	kit:part(Vector3.new(1, 3.5, 1), CFrame.new(-8, 1.75, -65), C.DarkConcrete, Enum.Material.Metal)
	for i = 0, 3 do
		local stripe = if i % 2 == 0 then Color3.fromRGB(200, 40, 35) else Color3.new(1, 1, 1)
		kit:part(Vector3.new(4, 0.6, 0.6), CFrame.new(-5.5 + i * 4, 3.2, -65), stripe, Enum.Material.SmoothPlastic)
	end
	kit:part(Vector3.new(5, 8, 5), CFrame.new(-17, 4, -61), C.Olive)
	kit:part(Vector3.new(6.5, 0.6, 6.5), CFrame.new(-17, 8.3, -61), C.DarkConcrete)
	kit:part(Vector3.new(3.5, 2, 0.2), CFrame.new(-17, 5.5, -58.45), Color3.fromRGB(40, 55, 70), Enum.Material.Glass)

	-- The statue of Joanna Moore and Eddie Moore on a stone pedestal, facing the courtyard (+z).
	kit:part(Vector3.new(18, 1, 11), CFrame.new(0, 0.5, 0), C.DarkConcrete, Enum.Material.Slate)
	kit:part(Vector3.new(15, 4, 8), CFrame.new(0, 3, 0), STONE_SHADE, Enum.Material.Slate)
	kit:part(Vector3.new(16, 0.5, 9), CFrame.new(0, 5.25, 0), STONE_SHADE, Enum.Material.Slate)
	local P = 5.5 -- pedestal top, where the figures stand
	local function figure(cx: number, inner: number)
		-- `inner` points toward the partner; that arm reaches across and the hands touch at x = 0.
		for _, dx in { -0.75, 0.75 } do
			kit:part(Vector3.new(1.4, 3, 1.4), CFrame.new(cx + dx, P + 1.5, 0), STONE, Enum.Material.Marble)
		end
		kit:part(Vector3.new(3, 3, 1.5), CFrame.new(cx, P + 4.5, 0), STONE, Enum.Material.Marble)
		kit:part(Vector3.new(1.8, 1.8, 1.8), CFrame.new(cx, P + 6.9, 0), STONE, Enum.Material.Marble)
		kit:part(Vector3.new(1.4, 3, 1.4), CFrame.new(cx - inner * 2.2, P + 4.5, 0), STONE, Enum.Material.Marble)
		local shoulder = Vector3.new(cx + inner * 2.2, P + 5.6, 0)
		local hand = Vector3.new(-inner * 0.6, P + 3.3, 0.4)
		local reach = hand - shoulder
		local arm = Vector3.new(1.4, 1.4, reach.Magnitude + 0.7)
		kit:part(arm, CFrame.lookAt((shoulder + hand) / 2, hand), STONE, Enum.Material.Marble)
		kit:part(Vector3.new(1.2, 1.2, 1.2), CFrame.new(hand), STONE, Enum.Material.Marble)
	end
	-- Joanna on the viewer's left with shoulder-length hair; Eddie on the right in a field cap.
	figure(-4, 1)
	kit:part(Vector3.new(2, 0.4, 2), CFrame.new(-4, P + 7.95, 0), STONE_SHADE, Enum.Material.Marble)
	kit:part(Vector3.new(2, 2.8, 0.5), CFrame.new(-4, P + 6.6, -1.1), STONE_SHADE, Enum.Material.Marble)
	figure(4, -1)
	kit:part(Vector3.new(2, 0.6, 2), CFrame.new(4, P + 8.1, 0), STONE_SHADE, Enum.Material.Marble)
	kit:part(Vector3.new(2, 0.25, 1), CFrame.new(4, P + 7.9, 1.4), STONE_SHADE, Enum.Material.Marble)

	local plaqueAt = CFrame.lookAt(Vector3.new(0, 3, 4.2), Vector3.new(0, 3, 10))
	local plaque = kit:sign(plaqueAt, "JOANNA MOORE  &  EDDIE MOORE", BRONZE, 13)
	boardOf(plaque).Size = Vector3.new(13, 3, 0.4)
	plaque.TextColor3 = GOLD
	plaque.Position = UDim2.fromScale(0, 0.08)
	plaque.Size = UDim2.fromScale(1, 0.5)
	local dedication = plaque:Clone() :: TextLabel
	dedication.Text = "Military Duels is dedicated to you"
	dedication.Font = Enum.Font.GothamMedium
	dedication.Position = UDim2.fromScale(0, 0.62)
	dedication.Size = UDim2.fromScale(1, 0.28)
	dedication.Parent = plaque.Parent

	-- Flag poles flanking the statue: Navy & Gold (the default HUD colors) and olive drab.
	for _, x in { -1, 1 } do
		local field = if x < 0 then NAVY else C.Olive
		local stripe = if x < 0 then GOLD else C.Sandbag
		local px, pz = x * 13, -12
		kit:part(Vector3.new(2, 1, 2), CFrame.new(px, 0.5, pz), C.DarkConcrete)
		kit:part(Vector3.new(26, 0.6, 0.6), CFrame.new(px, 13, pz) * UPRIGHT, METAL, Enum.Material.Metal, "Cylinder")
		kit:part(Vector3.new(1, 1, 1), CFrame.new(px, 26.3, pz), GOLD, Enum.Material.Metal, "Ball")
		kit:part(Vector3.new(6, 3.6, 0.15), CFrame.new(px + x * 3.3, 23.6, pz), field, Enum.Material.Fabric)
		kit:part(Vector3.new(6, 0.7, 0.2), CFrame.new(px + x * 3.3, 23.6, pz), stripe, Enum.Material.Fabric)
	end

	-- Shop (west) and armory (east): decorative two-door-wide buildings facing the courtyard. `cf` is
	-- the ground-level center of the front wall, looking out; the building extends toward local +z.
	local function building(cf: CFrame, title: string, signColor: Color3, walls: Color3)
		kit:part(Vector3.new(24, 0.4, 14), cf * CFrame.new(0, 0.2, 7), C.DarkConcrete)
		kit:wall(cf, 24, 12, { { -9, -3, 0, 8 }, { 1, 10, 3, 7 } }, walls)
		kit:part(Vector3.new(24, 12, 1), cf * CFrame.new(0, 6, 14), walls)
		for _, x in { -12, 12 } do
			kit:part(Vector3.new(1, 12, 14), cf * CFrame.new(x, 6, 7), walls)
		end
		kit:part(Vector3.new(26, 1, 16), cf * CFrame.new(0, 12.5, 7), C.DarkConcrete)
		kit:part(Vector3.new(16, 7, 1.5), cf * CFrame.new(0, 3.5, 12.6), C.Wood, Enum.Material.WoodPlanks)
		kit:sign(cf * CFrame.new(0, 10, -0.75), title, signColor, 16)
	end
	local shop = CFrame.lookAt(Vector3.new(-52, 0, 0), Vector3.new(-40, 0, 0))
	building(shop, "SHOP", Color3.fromRGB(196, 150, 40), Color3.fromRGB(190, 178, 150))
	kit:part(Vector3.new(10, 3.5, 2), shop * CFrame.new(5.5, 1.75, -1.6), C.Wood, Enum.Material.WoodPlanks)
	kit:part(Vector3.new(10.6, 0.3, 2.6), shop * CFrame.new(5.5, 3.65, -1.6), C.DarkConcrete, Enum.Material.Wood)
	local awning = shop * CFrame.new(5.5, 8.3, -2) * CFrame.Angles(-0.3, 0, 0)
	kit:part(Vector3.new(12, 0.3, 4.5), awning, Color3.fromRGB(180, 50, 40), Enum.Material.Fabric)

	local armory = CFrame.lookAt(Vector3.new(52, 0, 0), Vector3.new(40, 0, 0))
	building(armory, "ARMORY", C.Olive, C.Concrete)
	kit:sandbags(armory * CFrame.new(5.5, 0, -2.5), 9)
	kit:sandbags(armory * CFrame.new(-14.5, 0, -2.5) * CFrame.Angles(0, math.pi / 2, 0), 5)
	kit:crates(armory * CFrame.new(-22, 0, 4))

	-- Leaderboard: a header sign over a tall navy board, angled toward the spawn point.
	local lb = CFrame.lookAt(Vector3.new(28, 0, -24), Vector3.new(0, 0, 22))
	for _, x in { -8.6, 8.6 } do
		kit:part(Vector3.new(0.8, 19, 0.8), lb * CFrame.new(x, 9.5, 0.4), C.DarkConcrete, Enum.Material.Metal)
	end
	local header = kit:sign(lb * CFrame.new(0, 17, 0), "LEADERBOARD", C.Olive, 16)
	header.TextColor3 = GOLD
	local leaderboard = kit:sign(lb * CFrame.new(0, 9, 0), "", NAVY, 16)
	boardOf(leaderboard).Size = Vector3.new(16, 12, 0.5)
	leaderboard.TextScaled = true
	leaderboard.TextWrapped = true
	leaderboard.TextYAlignment = Enum.TextYAlignment.Top
	leaderboard.TextXAlignment = Enum.TextXAlignment.Left
	leaderboard.Font = Enum.Font.GothamBold
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = leaderboard

	-- Sandbag emplacement opposite the leaderboard, plus sandbag decor along the south wall.
	kit:sandbags(CFrame.new(-28, 0, -18), 10)
	for _, side in { -1, 1 } do
		kit:sandbags(CFrame.new(-28 + side * 5, 0, -22) * CFrame.Angles(0, math.pi / 2, 0), 7)
		kit:sandbags(CFrame.new(side * 40, 0, 62), 10)
	end
	kit:crates(CFrame.new(-31, 0, -28))

	-- Benches around the statue and on the south lawn, all facing the statue.
	for _, b in { { -16, 6 }, { 16, 6 }, { -16, -6 }, { 16, -6 }, { -30, 42 }, { 30, 42 } } do
		local cf = CFrame.lookAt(Vector3.new(b[1], 0, b[2]), Vector3.zero)
		kit:part(Vector3.new(6, 0.4, 2), cf * CFrame.new(0, 1.9, 0), C.Wood, Enum.Material.WoodPlanks)
		kit:part(Vector3.new(6, 2, 0.3), cf * CFrame.new(0, 3, 0.9), C.Wood, Enum.Material.WoodPlanks)
		for _, x in { -2.5, 2.5 } do
			kit:part(Vector3.new(0.4, 1.7, 1.8), cf * CFrame.new(x, 0.85, 0), C.DarkConcrete, Enum.Material.Metal)
		end
	end

	local trunk = Color3.fromRGB(95, 70, 45)
	local leaf, leafLight = Color3.fromRGB(62, 110, 52), Color3.fromRGB(74, 124, 58)
	local trees = {
		{ -60, -48 },
		{ 60, -48 },
		{ -30, -54 },
		{ 30, -54 },
		{ -74, -30 },
		{ 74, -30 },
		{ -74, 30 },
		{ 74, 30 },
		{ -52, 52 },
		{ 52, 52 },
		{ -14, 54 },
		{ 14, 54 },
	}
	for _, t in trees do
		local x, z = t[1], t[2]
		kit:part(Vector3.new(10, 1.6, 1.6), CFrame.new(x, 5, z) * UPRIGHT, trunk, Enum.Material.Wood, "Cylinder")
		kit:part(Vector3.new(9, 9, 9), CFrame.new(x, 11.5, z), leaf, Enum.Material.Grass, "Ball")
		kit:part(Vector3.new(6, 6, 6), CFrame.new(x + 2, 14, z + 1), leafLight, Enum.Material.Grass, "Ball")
	end

	-- Practice range on the south lawn, behind the spawn: shooters face away from the courtyard (+z)
	-- down three lanes that fit between the two south trees (x = ±14) and end at a berm by the wall.
	local FIRE_Z, BERM_Z = 35.5, 65.5
	local laneStart, laneEnd = FIRE_Z + 1, BERM_Z - 1
	local laneMid, laneLen = (laneStart + laneEnd) / 2, laneEnd - laneStart
	kit:fill(CFrame.new(0, -1, laneMid), Vector3.new(18, 2, laneLen), Enum.Material.Ground)
	kit:part(Vector3.new(44, 0.4, 8), CFrame.new(0, 0.2, 33), C.Concrete)
	kit:part(Vector3.new(18, 3.2, 1.5), CFrame.new(0, 2, FIRE_Z), C.Wood, Enum.Material.WoodPlanks)
	kit:part(Vector3.new(18.6, 0.3, 2), CFrame.new(0, 3.75, FIRE_Z), C.DarkConcrete, Enum.Material.Metal)
	for _, x in { -9, -3, 3, 9 } do
		kit:part(Vector3.new(1, 2.5, laneLen), CFrame.new(x, 1.25, laneMid), C.DarkConcrete)
	end
	kit:part(Vector3.new(20, 10, 2), CFrame.new(0, 5, BERM_Z), C.DarkConcrete)
	kit:sandbags(CFrame.new(0, 0, BERM_Z - 2), 18)
	for _, x in { -10, 10 } do
		kit:part(Vector3.new(0.8, 11, 0.8), CFrame.new(x, 5.5, 30), C.DarkConcrete, Enum.Material.Metal)
	end
	local rangeSignAt = CFrame.lookAt(Vector3.new(0, 9, 30), Vector3.new(0, 9, 0))
	local rangeSign = kit:sign(rangeSignAt, "PRACTICE RANGE · TRY ANY WEAPON", C.Olive, 20)
	rangeSign.TextColor3 = GOLD
	-- The same text on the back of the board, readable from the firing line.
	local rangeBack = (rangeSign.Parent :: SurfaceGui):Clone()
	rangeBack.Face = Enum.NormalId.Back
	rangeBack.Parent = boardOf(rangeSign)

	local racks: { CFrame } = {}
	for _, x in { -20, -16, -12, 12, 16, 20 } do
		kit:part(Vector3.new(2.4, 3, 1.4), CFrame.new(x, 1.9, FIRE_Z), C.Wood, Enum.Material.WoodPlanks)
		kit:part(Vector3.new(2.8, 0.3, 1.8), CFrame.new(x, 3.55, FIRE_Z), C.Olive, Enum.Material.Metal)
		table.insert(racks, kit:at(CFrame.lookAt(Vector3.new(x, 3.7, FIRE_Z), Vector3.new(x, 3.7, FIRE_Z + 1))))
	end
	local targets: { CFrame } = {}
	for _, x in { -6, 0, 6 } do
		local stand = Vector3.new(x, 3, BERM_Z - 5)
		table.insert(targets, kit:at(CFrame.lookAt(stand, Vector3.new(x, 3, FIRE_Z))))
	end

	kit:boundary(HALF_X, HALF_Z)
	kit:clearUnderBuildings(Enum.Material.Concrete)

	return {
		spawn = kit:at(CFrame.lookAt(Vector3.new(0, 3.5, 22), Vector3.new(0, 3.5, 0))),
		leaderboard = leaderboard,
		range = {
			-- Starts a rack prompt's reach (9) behind the firing line, so taking a weapon is always "on the range".
			min = kit.origin + Vector3.new(-22, -2, FIRE_Z - 10),
			max = kit.origin + Vector3.new(22, 30, BERM_Z + 1),
			racks = racks,
			targets = targets,
		},
	}
end
