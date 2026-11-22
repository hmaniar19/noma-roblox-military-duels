--!strict
-- Drop-in rides for the round start: code-built vehicles and parachutes. Every part is anchored
-- and inert; the caller parents the model and flies it with PivotTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Vehicles = {}

export type Kind = string -- "Helicopter" | "Truck" | "ArmoredCar"
export type Ride = {
	model: Model,
	seats: { CFrame },
	door: { CFrame }?,
	spin: BasePart?,
}

local OLIVE = Color3.fromRGB(86, 94, 62)
local DARK = Color3.fromRGB(52, 56, 58)
local TIRE = Color3.fromRGB(28, 28, 30)
local CANVAS = Color3.fromRGB(118, 112, 80)
local WHITE = Color3.fromRGB(245, 245, 240)
local LINE = Color3.fromRGB(210, 210, 205)

local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local ALONG = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z
local BACK = CFrame.Angles(0, math.pi, 0)
local FLIP = CFrame.Angles(0, 0, math.pi)

type Mat = Enum.Material?

local function setup(p: BasePart, m: Model, size: Vector3, cf: CFrame, color: Color3, material: Mat): BasePart
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = m
	return p
end

local function box(m: Model, size: Vector3, cf: CFrame, color: Color3, material: Mat): BasePart
	return setup(Instance.new("Part"), m, size, cf, color, material)
end

local function wedge(m: Model, size: Vector3, cf: CFrame, color: Color3, material: Mat): BasePart
	return setup(Instance.new("WedgePart"), m, size, cf, color, material)
end

local function cyl(m: Model, length: number, diameter: number, cf: CFrame, color: Color3, material: Mat): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	return setup(p, m, Vector3.new(length, diameter, diameter), cf, color, material)
end

local at = CFrame.new

-- The root keeps its real place in the build; PivotOffset puts the model pivot at the origin.
local function finish(m: Model, root: BasePart)
	m.PrimaryPart = root
	root.PivotOffset = root.CFrame:Inverse()
end

local function helicopter(m: Model, hud: Color3, band: Color3): Ride
	-- skids and struts (pivot is the bottom of the skids)
	for _, s in { -1, 1 } do
		cyl(m, 12, 0.4, at(3 * s, 0.2, 0) * ALONG, DARK)
		for _, z in { -3, 3 } do
			box(m, Vector3.new(0.3, 1.6, 0.3), at(3 * s, 1, z), DARK)
		end
	end

	-- cabin: floor, roof, rear wall and the wall segments either side of the open doors
	local root = box(m, Vector3.new(7, 0.5, 12), at(0, 2.05, 0), DARK, Enum.Material.DiamondPlate)
	box(m, Vector3.new(7, 0.8, 12), at(0, 7.4, 0), OLIVE)
	box(m, Vector3.new(7, 4.7, 0.4), at(0, 4.65, 5.8), OLIVE)
	for _, s in { -1, 1 } do
		box(m, Vector3.new(0.4, 4.7, 4), at(3.3 * s, 4.65, -4), OLIVE)
		box(m, Vector3.new(0.4, 4.7, 2), at(3.3 * s, 4.65, 5), OLIVE)
		box(m, Vector3.new(0.2, 4.2, 3.6), at(3.65 * s, 4.6, 5.8), OLIVE) -- slid-back door
		box(m, Vector3.new(1.4, 0.3, 0.3), at(3.9 * s, 7.2, 1), DARK) -- rope hoist arm
	end
	box(m, Vector3.new(7.1, 0.3, 12.1), at(0, 7.15, 0), band) -- roof-edge band, clear of the doorway

	-- nose and cockpit glass
	box(m, Vector3.new(6.6, 1.6, 3), at(0, 2.6, -7.5), OLIVE)
	box(m, Vector3.new(6.2, 3.6, 3), at(0, 5, -7.5), DARK, Enum.Material.Glass).Transparency = 0.4
	box(m, Vector3.new(6.6, 0.8, 3), at(0, 7.2, -7.5), OLIVE)
	wedge(m, Vector3.new(6.2, 3.6, 1.6), at(0, 5, -9.8), DARK, Enum.Material.Glass).Transparency = 0.4
	wedge(m, Vector3.new(6.6, 1.6, 1.6), at(0, 2.6, -9.8) * FLIP, OLIVE)

	-- engine housing, tail fairing, boom, fin, stabilizer
	box(m, Vector3.new(4, 1.4, 6), at(0, 8.5, 0.5), OLIVE)
	wedge(m, Vector3.new(5, 3, 3), at(0, 5.5, 7.5) * BACK, OLIVE)
	box(m, Vector3.new(1.6, 1.6, 14), at(0, 6, 13), OLIVE)
	box(m, Vector3.new(1.7, 0.4, 10), at(0, 6, 13), hud)
	box(m, Vector3.new(0.3, 3.5, 2), at(0, 7.8, 19.2), OLIVE)
	box(m, Vector3.new(0.32, 0.8, 2.02), at(0, 9.2, 19.2), hud)
	box(m, Vector3.new(4, 0.2, 1.2), at(0, 6, 18), OLIVE)

	-- tail rotor
	cyl(m, 0.4, 0.5, at(0.35, 8, 19.4), DARK)
	box(m, Vector3.new(0.12, 3.2, 0.4), at(0.6, 8, 19.4), DARK)
	box(m, Vector3.new(0.12, 0.4, 3.2), at(0.6, 8, 19.4), DARK)

	-- main rotor: the hub is the spin part and carries both blades through welds
	cyl(m, 1.2, 0.6, at(0, 9.6, 0) * UP, DARK)
	local spin = box(m, Vector3.new(1.4, 0.5, 1.4), at(0, 10.4, 0), DARK)
	for _, a in { math.pi / 4, -math.pi / 4 } do
		local blade = box(m, Vector3.new(26, 0.15, 1), at(0, 10.5, 0) * CFrame.Angles(0, a, 0), DARK)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = spin
		weld.Part1 = blade
		weld.Parent = spin
	end

	finish(m, root)
	return {
		model = m,
		seats = {
			CFrame.lookAt(Vector3.new(4.2, 3, 1), Vector3.new(5.2, 3, 1)),
			CFrame.lookAt(Vector3.new(-4.2, 3, 1), Vector3.new(-5.2, 3, 1)),
		},
		door = { at(4.4, 7, 1), at(-4.4, 7, 1) },
		spin = spin,
	}
end

local function truck(m: Model, hud: Color3, band: Color3): Ride
	for _, s in { -1, 1 } do
		for _, z in { -7, 4, 7.4 } do
			cyl(m, 1.2, 3.2, at(3.4 * s, 1.6, z), TIRE, Enum.Material.SmoothPlastic)
			cyl(m, 1.3, 1.4, at(3.4 * s, 1.6, z), DARK)
		end
		box(m, Vector3.new(1.4, 0.4, 4), at(3.4 * s, 3.4, -7), OLIVE) -- front fender
	end
	local root = box(m, Vector3.new(5, 0.8, 21), at(0, 2.4, -0.5), DARK)

	-- cab and hood
	box(m, Vector3.new(7, 3.6, 5), at(0, 4.6, -8), OLIVE)
	box(m, Vector3.new(6, 1.4, 0.2), at(0, 5.4, -10.55), DARK, Enum.Material.Glass).Transparency = 0.4
	box(m, Vector3.new(7.05, 1.2, 2), at(0, 5.5, -8.5), DARK, Enum.Material.Glass).Transparency = 0.4
	box(m, Vector3.new(7.06, 1, 1.4), at(0, 4, -7.5), band)
	box(m, Vector3.new(6.4, 2.2, 2), at(0, 3.9, -11.5), OLIVE)
	box(m, Vector3.new(5, 1.4, 0.2), at(0, 3.9, -12.55), DARK)
	box(m, Vector3.new(7, 0.6, 0.4), at(0, 2.6, -12.7), DARK)

	-- bed, benches and the canvas cover (open at the back)
	box(m, Vector3.new(7, 0.5, 15), at(0, 3.05, 2.5), OLIVE, Enum.Material.WoodPlanks)
	box(m, Vector3.new(7, 1.4, 0.3), at(0, 4, -4.85), OLIVE)
	for _, s in { -1, 1 } do
		box(m, Vector3.new(0.3, 1.4, 15), at(3.35 * s, 4, 2.5), OLIVE)
		box(m, Vector3.new(1.2, 0.35, 9), at(2.6 * s, 3.6, 4), DARK, Enum.Material.WoodPlanks)
		box(m, Vector3.new(0.2, 3.5, 13.6), at(3.4 * s, 6.45, 2.1), CANVAS, Enum.Material.Fabric)
		box(m, Vector3.new(0.1, 0.6, 12), at(3.55 * s, 7.2, 2.1), hud)
	end
	box(m, Vector3.new(7, 0.25, 13.6), at(0, 8.3, 2.1), CANVAS, Enum.Material.Fabric)
	box(m, Vector3.new(7, 3.5, 0.2), at(0, 6.45, -4.7), CANVAS, Enum.Material.Fabric)
	box(m, Vector3.new(0.15, 3, 0.15), at(-3, 7.9, -6), DARK) -- flagpole on the cab
	box(m, Vector3.new(0.05, 1, 1.6), at(-3, 8.9, -5.1), hud, Enum.Material.Fabric)
	finish(m, root)
	return {
		model = m,
		seats = {
			CFrame.lookAt(Vector3.new(1.6, 4.2, 6), Vector3.new(0, 4.2, 6)),
			CFrame.lookAt(Vector3.new(-1.6, 4.2, 6), Vector3.new(0, 4.2, 6)),
		},
	}
end

local function armoredCar(m: Model, hud: Color3, band: Color3): Ride
	for _, s in { -1, 1 } do
		for _, z in { -5.5, 5.5 } do
			cyl(m, 1.6, 3.8, at(3.6 * s, 1.9, z), TIRE, Enum.Material.SmoothPlastic)
			cyl(m, 1.7, 1.6, at(3.6 * s, 1.9, z), DARK)
			box(m, Vector3.new(1.8, 0.4, 4.6), at(3.6 * s, 4, z), OLIVE)
		end
		-- sloped side armor (slope faces outward)
		wedge(m, Vector3.new(6.5, 1.4, 0.8), at(2.8 * s, 4.8, -0.75) * CFrame.Angles(0, -s * math.pi / 2, 0), OLIVE)
	end

	-- hull: lower box, front glacis, upper box, sloped front and rear, rear deck
	local root = box(m, Vector3.new(6.4, 2.2, 15), at(0, 3, 0.5), OLIVE)
	box(m, Vector3.new(6.45, 0.5, 13), at(0, 3.4, 0.5), hud)
	wedge(m, Vector3.new(6.4, 2.2, 2.5), at(0, 3, -8.25), OLIVE)
	box(m, Vector3.new(4.8, 1.4, 6.5), at(0, 4.8, -0.75), OLIVE)
	wedge(m, Vector3.new(4.8, 1.4, 3), at(0, 4.8, -5.5), OLIVE)
	wedge(m, Vector3.new(4.8, 1.4, 1.3), at(0, 4.8, 3.15) * BACK, OLIVE)
	box(m, Vector3.new(6, 0.1, 4.2), at(0, 4.15, 5.9), DARK, Enum.Material.DiamondPlate)

	-- turret with a short barrel
	cyl(m, 0.8, 3.4, at(0, 5.9, -1) * UP, DARK)
	box(m, Vector3.new(2.4, 1, 2.6), at(0, 6.8, -1), OLIVE)
	box(m, Vector3.new(0.8, 0.7, 0.4), at(0, 6.8, -2.45), DARK)
	cyl(m, 3, 0.35, at(0, 6.8, -3.8) * ALONG, DARK)

	-- rear hatch
	box(m, Vector3.new(2.6, 2, 0.25), at(0, 3, 8.1), DARK)
	box(m, Vector3.new(0.8, 0.15, 0.15), at(0, 3.2, 8.3), OLIVE)

	-- antenna with a team flag
	box(m, Vector3.new(0.1, 4, 0.1), at(2.8, 6.1, 7.5), DARK)
	box(m, Vector3.new(0.05, 0.9, 1.4), at(2.8, 7.6, 8.25), band, Enum.Material.Fabric)

	finish(m, root)
	return {
		model = m,
		seats = { at(1.4, 5.2, 5), at(-1.4, 5.2, 5) },
	}
end

local BUILDERS: { [string]: (Model, Color3, Color3) -> Ride } = {
	Helicopter = helicopter,
	Truck = truck,
	ArmoredCar = armoredCar,
}

function Vehicles.build(kind: Kind, team: Config.TeamId): Ride
	local builder = BUILDERS[kind]
	assert(builder, `unknown vehicle kind {kind}`)
	local colors = Config.Teams[team]
	local m = Instance.new("Model")
	m.Name = kind
	return builder(m, colors.hud, colors.armband)
end

-- A ram-air canopy arc about 10 wide with its crown 10 above the pivot; the lines meet at the shoulders.
function Vehicles.parachute(team: Config.TeamId): Model
	local hud = Config.Teams[team].hud
	local m = Instance.new("Model")
	m.Name = "Parachute"
	local radius, span, panels, depth = 6, math.rad(120), 7, 4.5
	local step = span / panels
	local width = 2 * radius * math.sin(step / 2) + 0.1
	local canopy: { BasePart } = {}
	for i = 1, panels do
		local cf = at(0, 4, 0) * CFrame.Angles(0, 0, span / 2 - (i - 0.5) * step) * at(0, radius, 0)
		canopy[i] = box(m, Vector3.new(width, 0.25, depth), cf, if i % 2 == 1 then hud else WHITE, Enum.Material.Fabric)
	end
	for k = 0, panels do
		local angle = k * step - span / 2
		local x, y = (radius - 0.15) * math.sin(angle), 4 + (radius - 0.15) * math.cos(angle)
		local shoulder = Vector3.new(math.sign(x) * 0.8, 1.6, 0)
		for _, z in { 0.3 - depth / 2, depth / 2 - 0.3 } do
			local top = Vector3.new(x, y, z)
			local cf = CFrame.lookAt((top + shoulder) / 2, top)
			box(m, Vector3.new(0.06, 0.06, (top - shoulder).Magnitude), cf, LINE, Enum.Material.SmoothPlastic)
		end
	end
	finish(m, canopy[(panels + 1) // 2])
	return m
end

return Vehicles
