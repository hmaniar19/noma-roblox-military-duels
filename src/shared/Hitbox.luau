--!strict
-- Pure hit math: ray vs the standard uniform hitboxes, damage, and spread.
-- No Instances, so the server can test rewound positions without moving parts.
local Config = require(script.Parent.Config)

local Hitbox = {}

-- Distance along a unit ray to an oriented box, or nil if it misses.
local function rayBox(origin: Vector3, dir: Vector3, maxDist: number, box: CFrame, size: Vector3): number?
	local o = box:PointToObjectSpace(origin)
	local d = box:VectorToObjectSpace(dir)
	local half = size / 2
	local tMin, tMax = 0, maxDist
	for _, axis in { "X", "Y", "Z" } do
		local oa: number = (o :: any)[axis]
		local da: number = (d :: any)[axis]
		local h: number = (half :: any)[axis]
		if math.abs(da) < 1e-8 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1 = (-h - oa) / da
			local t2 = (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end
Hitbox.rayBox = rayBox

-- Nearest zone hit by the ray on a combatant whose HumanoidRootPart is at `root`.
function Hitbox.cast(origin: Vector3, dir: Vector3, maxDist: number, root: CFrame): (Config.Zone?, number?)
	local bestZone: Config.Zone? = nil
	local bestDist = math.huge
	for _, hb in Config.Hitboxes do
		local t = rayBox(origin, dir, maxDist, root * CFrame.new(hb.offset), hb.size)
		if t and t < bestDist then
			bestZone, bestDist = hb.zone, t
		end
	end
	if bestZone then
		return bestZone, bestDist
	end
	return nil, nil
end

function Hitbox.damage(weapon: Config.Weapon, zone: Config.Zone, distance: number): number
	local scale = 1
	if distance > weapon.falloffStart then
		local a = math.clamp((distance - weapon.falloffStart) / (weapon.falloffEnd - weapon.falloffStart), 0, 1)
		scale = 1 + (weapon.minDamageScale - 1) * a
	end
	return weapon.damage * scale * Config.ZoneMultiplier[zone]
end

-- A random direction inside a cone of `degrees` around unit `dir`.
function Hitbox.spread(dir: Vector3, degrees: number, rng: Random): Vector3
	if degrees <= 0 then
		return dir
	end
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local spin = rng:NextNumber() * 2 * math.pi
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

function Hitbox.angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

return Hitbox
