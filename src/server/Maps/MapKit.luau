--!strict
-- Shared building kit for every map and the lobby. A kit is bound to a folder and a world origin;
-- every CFrame passed to it is map-local (ground level is y = 0 at the origin), so a map can be
-- built anywhere in the world.

local MapKit = {}

export type MapInfo = {
	id: string,
	name: string,
	spawns: { A: { CFrame }, B: { CFrame } }, -- two per side, world space
	boundsMin: Vector3,
	boundsMax: Vector3,
	waypoints: { Vector3 }, -- cover points for bots, world space
}

MapKit.Colors = {
	Concrete = Color3.fromRGB(165, 160, 150),
	DarkConcrete = Color3.fromRGB(120, 116, 108),
	Sandbag = Color3.fromRGB(176, 154, 112),
	Wood = Color3.fromRGB(120, 88, 56),
	Olive = Color3.fromRGB(86, 94, 62),
}
local C = MapKit.Colors

export type Kit = {
	folder: Folder,
	origin: Vector3,
	at: (self: Kit, cf: CFrame) -> CFrame,
	part: (self: Kit, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, kind: string?) -> BasePart,
	wall: (self: Kit, cf: CFrame, length: number, height: number, holes: { { number } }, color: Color3?) -> (),
	sandbags: (self: Kit, cf: CFrame, length: number) -> (),
	barrier: (self: Kit, cf: CFrame, length: number) -> (),
	crates: (self: Kit, cf: CFrame) -> (),
	sign: (self: Kit, cf: CFrame, text: string, color: Color3, width: number?) -> TextLabel,
	office: (self: Kit, cf: CFrame, wallColor: Color3?, trimColor: Color3?) -> (),
	tower: (self: Kit, cf: CFrame, color: Color3?) -> (),
	target: (self: Kit, cf: CFrame) -> (),
	fill: (self: Kit, cf: CFrame, size: Vector3, material: Enum.Material) -> (),
	ball: (self: Kit, center: Vector3, radius: number, material: Enum.Material) -> (),
	patch: (self: Kit, center: Vector3, radius: number, material: Enum.Material) -> (),
	hill: (self: Kit, x: number, z: number, height: number, material: Enum.Material) -> (),
	dip: (self: Kit, x: number, z: number, material: Enum.Material) -> (),
	boundary: (self: Kit, halfX: number, halfZ: number) -> (),
	clearUnderBuildings: (self: Kit, material: Enum.Material) -> (),
	info: (
		self: Kit,
		id: string,
		name: string,
		spawns: { A: { CFrame }, B: { CFrame } },
		waypoints: { Vector3 },
		halfX: number,
		halfZ: number
	) -> MapInfo,
}

local Kit = {}
Kit.__index = Kit

function MapKit.new(name: string, origin: Vector3): Kit
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return setmetatable({ folder = folder, origin = origin }, Kit) :: any
end

-- Map-local CFrame to world.
function Kit.at(self: Kit, cf: CFrame): CFrame
	return CFrame.new(self.origin) * cf
end

function Kit.part(
	self: Kit,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	elseif kind == "Truss" then
		p = Instance.new("TrussPart")
	elseif kind == "Cylinder" or kind == "Ball" then
		local shaped = Instance.new("Part")
		shaped.Shape = if kind == "Ball" then Enum.PartType.Ball else Enum.PartType.Cylinder
		p = shaped
	else
		p = Instance.new("Part")
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = self:at(cf)
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = self.folder
	return p
end

-- A wall of `length` x `height` along local X, centered on `cf` at its base, with rectangular holes
-- {x0, x1, y0, y1} in wall-local coordinates (x from -length/2, y from 0). Holes must not overlap in x.
function Kit.wall(self: Kit, cf: CFrame, length: number, height: number, holes: { { number } }, color: Color3?)
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
					self:part(Vector3.new(x1 - x0, s[2] - s[1], 1), cf * CFrame.new(mid), color or C.Concrete)
				end
			end
		end
	end
end

-- Body-high cover (the head stays exposed when standing, hidden when crouched).
function Kit.sandbags(self: Kit, cf: CFrame, length: number)
	self:part(Vector3.new(length, 3.5, 2), cf * CFrame.new(0, 1.75, 0), C.Sandbag, Enum.Material.Sand)
end

-- Full-height cover.
function Kit.barrier(self: Kit, cf: CFrame, length: number)
	self:part(Vector3.new(length, 7, 1.5), cf * CFrame.new(0, 3.5, 0), C.DarkConcrete)
end

function Kit.crates(self: Kit, cf: CFrame)
	self:part(Vector3.new(5, 5, 5), cf * CFrame.new(0, 2.5, 0), C.Wood, Enum.Material.WoodPlanks)
	self:part(Vector3.new(5, 5, 5), cf * CFrame.new(5.2, 2.5, 0.6), C.Wood, Enum.Material.WoodPlanks)
	self:part(
		Vector3.new(4, 4, 4),
		cf * CFrame.new(2.6, 7, 0.2) * CFrame.Angles(0, 0.3, 0),
		C.Wood,
		Enum.Material.WoodPlanks
	)
end

-- A board with text on its front face. Returns the label so callers can update it.
function Kit.sign(self: Kit, cf: CFrame, text: string, color: Color3, width: number?): TextLabel
	local board = self:part(Vector3.new(width or 14, 4, 0.5), cf, color, Enum.Material.SmoothPlastic)
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
	return label
end

-- Two-story building: 24 x 16, doors on both long sides, windows on every wall, a ramp onto a
-- landing flush with the second floor, and a roof. `cf` is the ground-level center.
function Kit.office(self: Kit, cf: CFrame, wallColor: Color3?, trimColor: Color3?)
	local walls, trim = wallColor or C.Concrete, trimColor or C.DarkConcrete
	local L, W, H = 24, 16, 10
	self:part(Vector3.new(L, 0.4, W), cf * CFrame.new(0, 0.2, 0), trim)
	local door = { -2.5, 2.5, 0, 7 }
	local lowWin = { { -9, -5, 3.5, 6.5 }, { 5, 9, 3.5, 6.5 } }
	local highWin = { { -9, -5, 3.5, 6.5 }, { -2, 2, 3.5, 6.5 }, { 5, 9, 3.5, 6.5 } }
	local function long(z: number, yaw: number)
		local holes = { door }
		for _, w in lowWin do
			table.insert(holes, w)
		end
		self:wall(cf * CFrame.new(0, 0, z) * CFrame.Angles(0, yaw, 0), L, H, holes, walls)
		self:wall(cf * CFrame.new(0, H, z) * CFrame.Angles(0, yaw, 0), L, H, highWin, walls)
	end
	long(W / 2, 0)
	long(-W / 2, math.pi)
	for _, x in { L / 2, -L / 2 } do
		local side = cf * CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
		self:wall(side, W - 1, H, { { -2, 2, 3.5, 6.5 } }, walls)
		self:wall(side * CFrame.new(0, H, 0), W - 1, H, { { -2, 2, 3.5, 6.5 } }, walls)
	end
	self:part(Vector3.new(L - 7, 1, W - 1), cf * CFrame.new(3.5, H + 0.5, 0), walls)
	self:part(Vector3.new(7, 1, 3), cf * CFrame.new(-L / 2 + 3.5, H + 0.5, -W / 2 + 2), walls)
	self:part(
		Vector3.new(6, H + 1, 11),
		cf * CFrame.new(-L / 2 + 3.5, (H + 1) / 2, 1) * CFrame.Angles(0, math.pi, 0),
		walls,
		nil,
		"Wedge"
	)
	self:part(Vector3.new(L, 1, W), cf * CFrame.new(0, 2 * H + 0.5, 0), trim)
end

-- Central watchtower: 18 studs up, ladders on the +x and -x sides arriving through railing gaps.
function Kit.tower(self: Kit, cf: CFrame, color: Color3?)
	local col = color or C.Olive
	local h = 18
	for _, x in { -5, 5 } do
		for _, z in { -5, 5 } do
			self:part(Vector3.new(1.5, h, 1.5), cf * CFrame.new(x, h / 2, z), col, Enum.Material.Metal)
		end
	end
	self:part(Vector3.new(12, 1, 12), cf * CFrame.new(0, h + 0.5, 0), col, Enum.Material.DiamondPlate)
	local rails = { { 0, 5.75, 12, 0.5 }, { 0, -5.75, 12, 0.5 } }
	for _, x in { 5.75, -5.75 } do
		table.insert(rails, { x, 3.75, 0.5, 4.5 })
		table.insert(rails, { x, -3.75, 0.5, 4.5 })
	end
	for _, s in rails do
		self:part(Vector3.new(s[3], 2.5, s[4]), cf * CFrame.new(s[1], h + 2.25, s[2]), col, Enum.Material.Metal)
	end
	for _, x in { -6.75, 6.75 } do
		self:part(Vector3.new(2, h + 1, 2), cf * CFrame.new(x, (h + 1) / 2, 0), col, Enum.Material.Metal, "Truss")
	end
	self:part(
		Vector3.new(5, 0.5, 5),
		cf * CFrame.new(0, h + 7, 0),
		Color3.fromRGB(200, 60, 40),
		Enum.Material.SmoothPlastic
	)
	self:part(Vector3.new(0.4, 6, 0.4), cf * CFrame.new(0, h + 4, 0), col, Enum.Material.Metal)
end

function Kit.target(self: Kit, cf: CFrame)
	self:part(Vector3.new(0.4, 5, 0.4), cf * CFrame.new(0, 2.5, 0), C.Wood, Enum.Material.Wood)
	local colors =
		{ Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 30), Color3.new(1, 1, 1), Color3.fromRGB(200, 30, 30) }
	for i, color in colors do
		local d = 4.5 - (i - 1) * 1.1
		self:part(
			Vector3.new(0.2 + i * 0.05, d, d),
			cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			color,
			Enum.Material.SmoothPlastic,
			"Cylinder"
		)
	end
end

-- Terrain helpers, all map-local.
function Kit.fill(self: Kit, cf: CFrame, size: Vector3, material: Enum.Material)
	workspace.Terrain:FillBlock(self:at(cf), size, material)
end

function Kit.ball(self: Kit, center: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(self.origin + center, radius, material)
end

-- Repaints the ground surface in a circle without changing its height.
function Kit.patch(self: Kit, center: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillCylinder(CFrame.new(self.origin + Vector3.new(center.X, -1, center.Z)), 2, radius, material)
end

-- A mound rising `height` studs (cover to crouch behind).
function Kit.hill(self: Kit, x: number, z: number, height: number, material: Enum.Material)
	local r = 11.5
	workspace.Terrain:FillBall(self.origin + Vector3.new(x, height - r, z), r, material)
end

-- A shallow dip about 3 studs deep.
function Kit.dip(self: Kit, x: number, z: number, material: Enum.Material)
	workspace.Terrain:FillBall(self.origin + Vector3.new(x, 3.5, z), 7, Enum.Material.Air)
	workspace.Terrain:FillBall(self.origin + Vector3.new(x, -5.5, z), 3, material)
end

-- Invisible walls around the play area (bullets pass through them; the movement check enforces it).
function Kit.boundary(self: Kit, halfX: number, halfZ: number)
	for _, s in
		{
			{ 0, halfZ, halfX * 2, 1 },
			{ 0, -halfZ, halfX * 2, 1 },
			{ halfX, 0, 1, halfZ * 2 },
			{ -halfX, 0, 1, halfZ * 2 },
		}
	do
		local w = self:part(Vector3.new(s[3], 120, s[4]), CFrame.new(s[1], 50, s[2]), Color3.new(), nil)
		w.Transparency = 1
		w.CanQuery = false
	end
end

-- Bare ground under everything built at ground level, so grass blades don't poke through floors.
function Kit.clearUnderBuildings(self: Kit, material: Enum.Material)
	for _, p in self.folder:GetDescendants() do
		if
			p:IsA("BasePart")
			and p.Transparency < 1
			and p.Position.Y - self.origin.Y - p.Size.Y / 2 < 0.8
			and p.Size.Y < 30
		then
			local flat = p.CFrame - p.CFrame.Position + Vector3.new(p.Position.X, self.origin.Y - 1, p.Position.Z)
			workspace.Terrain:FillBlock(flat, Vector3.new(p.Size.X + 1, 2, p.Size.Z + 1), material)
		end
	end
end

-- Packages a finished map. Spawns and waypoints are given map-local and converted to world space.
function Kit.info(
	self: Kit,
	id: string,
	name: string,
	spawns: { A: { CFrame }, B: { CFrame } },
	waypoints: { Vector3 },
	halfX: number,
	halfZ: number
): MapInfo
	local world = { A = {}, B = {} } :: { A: { CFrame }, B: { CFrame } }
	for i, cf in spawns.A do
		world.A[i] = self:at(cf)
	end
	for i, cf in spawns.B do
		world.B[i] = self:at(cf)
	end
	local points = {}
	for i, p in waypoints do
		points[i] = self.origin + p
	end
	return {
		id = id,
		name = name,
		spawns = world,
		boundsMin = self.origin + Vector3.new(-halfX + 1, -12, -halfZ + 1),
		boundsMax = self.origin + Vector3.new(halfX - 1, 60, halfZ - 1),
		waypoints = points,
	}
end

return MapKit
