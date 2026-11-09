--!strict
--[[
    Pure data side of a hit effect: a hit kind is a spec (count, speed, size, lifetime, glow) the
    game defines as data; this module validates the table and turns a spec into the numbers a
    single reused emitter needs. Loads under Lune. The emitter is `client/presenters/HitFxEmitter`.
]]

export type HitSpec = {
    -- Particles per burst.
    count: number,
    speedMin: number,
    speedMax: number,
    size: number,
    -- Seconds the longest particle lives.
    lifetime: number,
    -- 0 (matte) to 1 (fully emissive).
    glow: number,
}

export type EmitterSettings = {
    count: number,
    speedMin: number,
    speedMax: number,
    size: number,
    lifetimeMin: number,
    lifetimeMax: number,
    glow: number,
}

local HitFx = {}

HitFx.MAX_COUNT = 40 -- chosen, not sourced: a tap burst must stay cheap on phones
HitFx.LIFETIME_SPREAD = 0.7 -- chosen: the shortest particle lives 70 % of the longest

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- One problem per invalid kind (empty when valid).
function HitFx.validate(kinds: { [string]: HitSpec }): { string }
    local problems: { string } = {}
    local ids: { string } = {}
    for id in kinds do
        table.insert(ids, id)
    end
    table.sort(ids)
    for _, id in ids do
        local spec = kinds[id]
        local numbers = { spec.count, spec.speedMin, spec.speedMax, spec.size, spec.lifetime }
        for _, value in numbers do
            if not isFinite(value) or value <= 0 then
                table.insert(problems, `hit kind "{id}" needs positive finite numbers`)
                break
            end
        end
        if spec.count > HitFx.MAX_COUNT then
            table.insert(problems, `hit kind "{id}" count is above {HitFx.MAX_COUNT}`)
        end
        if spec.speedMax < spec.speedMin then
            table.insert(problems, `hit kind "{id}" speedMax is below speedMin`)
        end
        if not (spec.glow >= 0 and spec.glow <= 1) then
            table.insert(problems, `hit kind "{id}" glow must be from 0 to 1`)
        end
    end
    return problems
end

--- The emitter numbers of `kindId`, or nil when the kind is unknown.
function HitFx.settings(kinds: { [string]: HitSpec }, kindId: string): EmitterSettings?
    local spec = kinds[kindId]
    if spec == nil then
        return nil
    end
    return {
        count = spec.count,
        speedMin = spec.speedMin,
        speedMax = spec.speedMax,
        size = spec.size,
        lifetimeMin = spec.lifetime * HitFx.LIFETIME_SPREAD,
        lifetimeMax = spec.lifetime,
        glow = spec.glow,
    }
end

return HitFx
