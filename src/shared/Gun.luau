--!strict
-- Builds each weapon out of parts. The server uses it for the Tool other players see; the client
-- uses it for the first-person viewmodel. Barrels point along -Z of the Handle.
local Config = require(script.Parent.Config)

local Gun = {}

local METAL = Color3.fromRGB(38, 40, 44)
local POLYMER = Color3.fromRGB(70, 66, 56)
local WOOD = Color3.fromRGB(110, 72, 44)
local STEEL = Color3.fromRGB(190, 195, 200)

type Piece = { size: Vector3, at: CFrame, color: Color3, name: string? }

-- size, offset from the grip, color, and an optional name. The grip itself is the Handle.
-- "Mag" and "Pump" are moved by the client's reload animation.
local function P(size: Vector3, at: CFrame, color: Color3, name: string?): Piece
	return { size = size, at = at, color = color, name = name }
end

local SHAPES: { [Config.WeaponId]: { muzzle: Vector3, pieces: { Piece } } } = {
	AR = {
		muzzle = Vector3.new(0, 0.55, -3.35),
		pieces = {
			P(Vector3.new(0.35, 0.45, 2.4), CFrame.new(0, 0.5, -0.6), METAL),
			P(Vector3.new(0.18, 0.18, 1.6), CFrame.new(0, 0.55, -2.5), METAL),
			P(Vector3.new(0.3, 0.3, 1.0), CFrame.new(0, 0.5, -1.9), POLYMER),
			P(Vector3.new(0.25, 0.8, 0.45), CFrame.new(0, -0.1, -1.0), METAL, "Mag"),
			P(Vector3.new(0.3, 0.5, 1.1), CFrame.new(0, 0.35, 1.0), POLYMER),
			P(Vector3.new(0.12, 0.22, 0.6), CFrame.new(0, 0.85, -0.4), METAL),
		},
	},
	SMG = {
		muzzle = Vector3.new(0, 0.5, -2.1),
		pieces = {
			P(Vector3.new(0.35, 0.5, 1.6), CFrame.new(0, 0.5, -0.5), METAL),
			P(Vector3.new(0.16, 0.16, 0.6), CFrame.new(0, 0.5, -1.6), METAL),
			P(Vector3.new(0.22, 1.1, 0.35), CFrame.new(0, -0.25, -0.75), METAL, "Mag"),
			P(Vector3.new(0.12, 0.25, 0.7), CFrame.new(0, 0.45, 0.6), METAL),
		},
	},
	Shotgun = {
		muzzle = Vector3.new(0, 0.55, -3.6),
		pieces = {
			P(Vector3.new(0.35, 0.45, 1.4), CFrame.new(0, 0.5, -0.3), METAL),
			P(Vector3.new(0.26, 0.26, 2.4), CFrame.new(0, 0.6, -2.2), METAL),
			P(Vector3.new(0.3, 0.26, 1.0), CFrame.new(0, 0.3, -2.0), WOOD, "Pump"),
			P(Vector3.new(0.32, 0.55, 1.3), CFrame.new(0, 0.3, 1.0), WOOD),
		},
	},
	Pistol = {
		muzzle = Vector3.new(0, 0.5, -1.05),
		pieces = {
			P(Vector3.new(0.25, 0.32, 1.1), CFrame.new(0, 0.5, -0.4), METAL),
			P(Vector3.new(0.12, 0.12, 0.2), CFrame.new(0, 0.5, -1.0), METAL),
			P(Vector3.new(0.2, 0.3, 0.28), CFrame.new(0, -0.32, 0.02), METAL, "Mag"), -- base of the grip magazine
		},
	},
	Sniper = {
		muzzle = Vector3.new(0, 0.55, -4.3),
		pieces = {
			P(Vector3.new(0.35, 0.45, 2.2), CFrame.new(0, 0.5, -0.5), POLYMER),
			P(Vector3.new(0.16, 0.16, 2.6), CFrame.new(0, 0.55, -3.0), METAL),
			P(Vector3.new(0.3, 0.3, 1.3), CFrame.new(0, 1.0, -0.6), METAL), -- scope
			P(Vector3.new(0.25, 0.55, 0.4), CFrame.new(0, -0.05, -0.6), METAL, "Mag"),
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

-- Special weapons (Shop > WEAPONS): their own models, same stats as the weapon they replace.
local DT_RED = Color3.fromRGB(110, 8, 14)
local DT_GLOW = Color3.fromRGB(255, 40, 40)
local DT_GRIP = Color3.fromRGB(28, 20, 22)
local MW_BLUE = Color3.fromRGB(16, 30, 90)
local MW_GLOW = Color3.fromRGB(70, 150, 255)

local function sword(x: number, z: number): { Piece }
	return {
		P(Vector3.new(0.1, 0.32, 2.6), CFrame.new(x, 0.05, z - 1.6), DT_RED),
		P(Vector3.new(0.05, 0.06, 2.5), CFrame.new(x, 0.24, z - 1.6), DT_GLOW),
		P(Vector3.new(0.5, 0.14, 0.14), CFrame.new(x, 0, z - 0.3), DT_GRIP),
	}
end

local DOUBLE_TROUBLE = sword(0, 0)
for _, p in sword(-1.1, 0.3) do
	table.insert(DOUBLE_TROUBLE, p)
end
table.insert(DOUBLE_TROUBLE, P(Vector3.new(0.3, 0.7, 0.4), CFrame.new(-1.1, 0, 0.3), DT_GRIP)) -- second grip

local SPECIALS: { [string]: { muzzle: Vector3, handle: Color3, light: Color3, pieces: { Piece } } } = {
	DoubleTrouble = { muzzle = Vector3.new(0, 0.05, -2.9), handle = DT_GRIP, light = DT_GLOW, pieces = DOUBLE_TROUBLE },
	MothersWrath = {
		muzzle = SHAPES.AR.muzzle,
		handle = MW_BLUE,
		light = MW_GLOW,
		pieces = {
			P(Vector3.new(0.35, 0.45, 2.4), CFrame.new(0, 0.5, -0.6), MW_BLUE),
			P(Vector3.new(0.37, 0.07, 2.0), CFrame.new(0, 0.5, -0.6), MW_GLOW),
			P(Vector3.new(0.18, 0.18, 1.6), CFrame.new(0, 0.55, -2.5), MW_BLUE),
			P(Vector3.new(0.24, 0.24, 0.2), CFrame.new(0, 0.55, -3.2), MW_GLOW),
			P(Vector3.new(0.3, 0.3, 1.0), CFrame.new(0, 0.5, -1.9), MW_BLUE),
			P(Vector3.new(0.25, 0.8, 0.45), CFrame.new(0, -0.1, -1.0), MW_BLUE, "Mag"),
			P(Vector3.new(0.3, 0.5, 1.1), CFrame.new(0, 0.35, 1.0), MW_BLUE),
			P(Vector3.new(0.12, 0.22, 0.6), CFrame.new(0, 0.85, -0.4), MW_GLOW),
		},
	},
}

-- Returns the handle (grip) with the rest of the weapon welded to it, all parented to `parent`.
-- `Muzzle` is an Attachment on the handle at the barrel tip (blade tip for the knife). `skinId`
-- recolors the body (a knife blade stays steel) or, for a special weapon, swaps the whole model.
-- A special weapon's handle carries a "Tracer" color attribute and, for blades, a "Draw" sound.
function Gun.build(parent: Instance, id: Config.WeaponId, skinId: string?): Part
	local shape = SHAPES[id]
	local skin = nil
	for _, s in Config.Skins do
		if s.id == skinId and s.color and (s.weapon == nil or s.weapon == id) then
			skin = s
		end
	end
	local special = if skin and skin.weapon then SPECIALS[skin.id] else nil
	local function paint(part: Part, baseColor: Color3)
		if special then
			local glows = baseColor == DT_GLOW or baseColor == MW_GLOW
			part.Material = if glows then Enum.Material.Neon else Enum.Material.Metal
		elseif skin and baseColor ~= STEEL then
			part.Color = skin.color :: Color3
			part.Material = skin.material or Enum.Material.SmoothPlastic
		end
	end
	local handleColor = if special then special.handle elseif id == "Knife" then WOOD else POLYMER
	local handle = piece(parent, nil, Vector3.new(0.3, 0.7, 0.4), CFrame.identity, handleColor)
	handle.Name = "Handle"
	paint(handle, handleColor)
	local pieces: { Piece } = if special then special.pieces else shape.pieces
	for _, p in pieces do
		local part = piece(parent, handle, p.size, p.at, p.color)
		paint(part, p.color)
		if p.name then
			part.Name = p.name
		end
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = if special then special.muzzle else shape.muzzle
	muzzle.Parent = handle
	if special then
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range = special.light, 1.5, 6
		light.Parent = handle
		handle:SetAttribute("Tracer", special.light)
	end
	if special and id == "Knife" then
		local base = Instance.new("Attachment")
		base.Position = Vector3.new(0, 0.05, -0.4)
		base.Parent = handle
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = base, muzzle
		trail.Color = ColorSequence.new(DT_GLOW)
		trail.LightEmission = 1
		trail.Lifetime = 0.18
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = handle
		local draw = Instance.new("Sound")
		draw.Name = "Draw"
		draw.SoundId = "rbxasset://sounds/unsheath.wav" -- Roblox's built-in sword draw
		draw.Volume = 0.7
		draw.Parent = handle
	end
	return handle
end

return Gun
