--!strict
-- Builds each weapon out of parts. The server uses it for the Tool other players see; the client
-- uses it for the first-person viewmodel. Barrels point along -Z of the Handle.
local Config = require(script.Parent.Config)

local Gun = {}

local METAL = Color3.fromRGB(38, 40, 44)
local POLYMER = Color3.fromRGB(70, 66, 56)
local WOOD = Color3.fromRGB(110, 72, 44)
local STEEL = Color3.fromRGB(190, 195, 200)

type Piece = { size: Vector3, at: CFrame, color: Color3 }

-- size, offset from the grip, color. The grip itself is the Handle.
local function P(size: Vector3, at: CFrame, color: Color3): Piece
	return { size = size, at = at, color = color }
end

local SHAPES: { [Config.WeaponId]: { muzzle: Vector3, pieces: { Piece } } } = {
	AR = {
		muzzle = Vector3.new(0, 0.55, -3.35),
		pieces = {
			P(Vector3.new(0.35, 0.45, 2.4), CFrame.new(0, 0.5, -0.6), METAL),
			P(Vector3.new(0.18, 0.18, 1.6), CFrame.new(0, 0.55, -2.5), METAL),
			P(Vector3.new(0.3, 0.3, 1.0), CFrame.new(0, 0.5, -1.9), POLYMER),
			P(Vector3.new(0.25, 0.8, 0.45), CFrame.new(0, -0.1, -1.0), METAL),
			P(Vector3.new(0.3, 0.5, 1.1), CFrame.new(0, 0.35, 1.0), POLYMER),
			P(Vector3.new(0.12, 0.22, 0.6), CFrame.new(0, 0.85, -0.4), METAL),
		},
	},
	SMG = {
		muzzle = Vector3.new(0, 0.5, -2.1),
		pieces = {
			P(Vector3.new(0.35, 0.5, 1.6), CFrame.new(0, 0.5, -0.5), METAL),
			P(Vector3.new(0.16, 0.16, 0.6), CFrame.new(0, 0.5, -1.6), METAL),
			P(Vector3.new(0.22, 1.1, 0.35), CFrame.new(0, -0.25, -0.75), METAL),
			P(Vector3.new(0.12, 0.25, 0.7), CFrame.new(0, 0.45, 0.6), METAL),
		},
	},
	Shotgun = {
		muzzle = Vector3.new(0, 0.55, -3.6),
		pieces = {
			P(Vector3.new(0.35, 0.45, 1.4), CFrame.new(0, 0.5, -0.3), METAL),
			P(Vector3.new(0.26, 0.26, 2.4), CFrame.new(0, 0.6, -2.2), METAL),
			P(Vector3.new(0.3, 0.26, 1.0), CFrame.new(0, 0.3, -2.0), WOOD),
			P(Vector3.new(0.32, 0.55, 1.3), CFrame.new(0, 0.3, 1.0), WOOD),
		},
	},
	Pistol = {
		muzzle = Vector3.new(0, 0.5, -1.05),
		pieces = {
			P(Vector3.new(0.25, 0.32, 1.1), CFrame.new(0, 0.5, -0.4), METAL),
			P(Vector3.new(0.12, 0.12, 0.2), CFrame.new(0, 0.5, -1.0), METAL),
		},
	},
	Sniper = {
		muzzle = Vector3.new(0, 0.55, -4.3),
		pieces = {
			P(Vector3.new(0.35, 0.45, 2.2), CFrame.new(0, 0.5, -0.5), POLYMER),
			P(Vector3.new(0.16, 0.16, 2.6), CFrame.new(0, 0.55, -3.0), METAL),
			P(Vector3.new(0.3, 0.3, 1.3), CFrame.new(0, 1.0, -0.6), METAL), -- scope
			P(Vector3.new(0.25, 0.55, 0.4), CFrame.new(0, -0.05, -0.6), METAL),
			P(Vector3.new(0.32, 0.6, 1.3), CFrame.new(0, 0.35, 1.1), POLYMER),
		},
	},
	Knife = {
		muzzle = Vector3.new(0, 0, -1.4),
		pieces = {
			P(Vector3.new(0.08, 0.3, 1.1), CFrame.new(0, 0.05, -0.85), STEEL), -- blade
			P(Vector3.new(0.22, 0.4, 0.12), CFrame.new(0, 0, -0.32), METAL), -- guard
		},
	},
}

local function piece(parent: Instance, handle: BasePart?, size: Vector3, offset: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = if color == WOOD then Enum.Material.Wood else Enum.Material.Metal
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if handle then
		p.CFrame = handle.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	p.Parent = parent
	return p
end

-- Returns the handle (grip) with the rest of the weapon welded to it, all parented to `parent`.
-- `Muzzle` is an Attachment on the handle at the barrel tip (blade tip for the knife).
function Gun.build(parent: Instance, id: Config.WeaponId): Part
	local shape = SHAPES[id]
	local handle =
		piece(parent, nil, Vector3.new(0.3, 0.7, 0.4), CFrame.identity, if id == "Knife" then WOOD else POLYMER)
	handle.Name = "Handle"
	for _, p in shape.pieces do
		piece(parent, handle, p.size, p.at, p.color)
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = shape.muzzle
	muzzle.Parent = handle
	return handle
end

return Gun
