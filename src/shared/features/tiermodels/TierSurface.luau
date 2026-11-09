--!strict
--[[
    Where the surface of a part model is, as pure geometry (ADR 0057). A node that hangs things on
    its model (cracks, ore veins, hazard bands, hit sparks, a crystal) cannot assume one fixed shape
    once every tier has its own; it asks the model. `radiusAt` marches inward from outside along a
    horizontal direction and answers the distance from the node axis to the first solid point at a
    height; `shell` lowers the height until something is there. Same pose convention as the rig and
    TierSilhouette: a part is rolled (Z), then pitched (X), then yawed (Y), then offset.
]]

local TierModelSource = require("../../ports/TierModelSource")

export type PartSpec = TierModelSource.PartSpec

local TierSurface = {}

TierSurface.STEP = 0.25 -- chosen, not measured: finer than the thinnest crack, cheap for 24 parts

--- Is the point (x, y, z), relative to the node origin, inside the part?
function TierSurface.contains(spec: PartSpec, x: number, y: number, z: number): boolean
    local px, py, pz = x - spec.offset.x, y - spec.offset.y, z - spec.offset.z
    local yaw, pitch, roll = math.rad(spec.yawDeg), math.rad(spec.pitchDeg), math.rad(spec.rollDeg)
    local cy, sy = math.cos(yaw), math.sin(yaw)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local cr, sr = math.cos(roll), math.sin(roll)
    -- Undo yaw, then pitch, then roll.
    local x1 = px * cy - pz * sy
    local z2 = px * sy + pz * cy
    local y1 = py * cp + z2 * sp
    local lz = -py * sp + z2 * cp
    local lx = x1 * cr + y1 * sr
    local ly = -x1 * sr + y1 * cr
    local halfX, halfY, halfZ = spec.size.x / 2, spec.size.y / 2, spec.size.z / 2
    if math.abs(lx) > halfX or math.abs(ly) > halfY or math.abs(lz) > halfZ then
        return false
    end
    if spec.shape == "ball" then
        return (lx / halfX) ^ 2 + (ly / halfY) ^ 2 + (lz / halfZ) ^ 2 <= 1
    elseif spec.shape == "cylinder" then
        return (ly / halfY) ^ 2 + (lz / halfZ) ^ 2 <= 1
    elseif spec.shape == "wedge" then
        -- The high end is at +z, as in TierSilhouette.
        return (ly + halfY) <= (lz + halfZ) / spec.size.z * spec.size.y
    end
    return true
end

local function solidAt(parts: { PartSpec }, x: number, y: number, z: number): boolean
    for _, spec in parts do
        if TierSurface.contains(spec, x, y, z) then
            return true
        end
    end
    return false
end

--- Highest solid point of the model, studs above the node origin (0 for no parts).
function TierSurface.height(parts: { PartSpec }): number
    local top = 0
    for _, spec in parts do
        top = math.max(top, spec.offset.y + math.max(spec.size.x, spec.size.y, spec.size.z) / 2)
    end
    return top
end

--- Distance from the node axis to the outermost point of the first solid met when walking inward
--- from `maxRadius` along `angle` (radians, 0 = +x, pi/2 = +z) at height `y`; nil when the ray
--- crosses nothing (a gap in an arch, a height above the model).
function TierSurface.radiusAt(
    parts: { PartSpec },
    angle: number,
    y: number,
    maxRadius: number
): number?
    local dx, dz = math.cos(angle), math.sin(angle)
    local radius = maxRadius
    while radius >= 0 do
        if solidAt(parts, dx * radius, y, dz * radius) then
            return radius
        end
        radius -= TierSurface.STEP
    end
    return nil
end

export type Spot = { radius: number, y: number }

--- The surface point at `angle` nearest to the wanted height: starts at `wantedY` and walks down
--- until the ray meets a solid. nil when nothing is there at any height down to the base.
function TierSurface.shell(
    parts: { PartSpec },
    angle: number,
    wantedY: number,
    maxRadius: number
): Spot?
    local y = math.min(wantedY, TierSurface.height(parts))
    while y >= 0 do
        local radius = TierSurface.radiusAt(parts, angle, y, maxRadius)
        if radius ~= nil then
            return { radius = radius, y = y }
        end
        y -= 0.5
    end
    return nil
end

return TierSurface
