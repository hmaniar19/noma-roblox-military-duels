--!strict
-- Builds the assault rifle out of parts. The server uses it for the Tool other players see;
-- the client uses it for the first-person viewmodel. Barrel points along -Z of the Handle.
local Gun = {}

local METAL = Color3.fromRGB(38, 40, 44)
local POLYMER = Color3.fromRGB(70, 66, 56)

local function piece(parent: Instance, handle: BasePart?, size: Vector3, offset: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
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

-- Returns the handle (grip) with the rest of the rifle welded to it, all parented to `parent`.
-- `Muzzle` is an Attachment on the handle at the barrel tip.
function Gun.build(parent: Instance): Part
	local handle = piece(parent, nil, Vector3.new(0.3, 0.7, 0.4), CFrame.identity, POLYMER)
	handle.Name = "Handle"
	piece(parent, handle, Vector3.new(0.35, 0.45, 2.4), CFrame.new(0, 0.5, -0.6), METAL) -- receiver
	piece(parent, handle, Vector3.new(0.18, 0.18, 1.6), CFrame.new(0, 0.55, -2.5), METAL) -- barrel
	piece(parent, handle, Vector3.new(0.3, 0.3, 1.0), CFrame.new(0, 0.5, -1.9), POLYMER) -- handguard
	piece(parent, handle, Vector3.new(0.25, 0.8, 0.45), CFrame.new(0, -0.1, -1.0), METAL) -- magazine
	piece(parent, handle, Vector3.new(0.3, 0.5, 1.1), CFrame.new(0, 0.35, 1.0), POLYMER) -- stock
	piece(parent, handle, Vector3.new(0.12, 0.22, 0.6), CFrame.new(0, 0.85, -0.4), METAL) -- sight rail
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.55, -3.35)
	muzzle.Parent = handle
	return handle
end

return Gun
