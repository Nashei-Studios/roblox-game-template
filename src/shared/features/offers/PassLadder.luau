--!strict
--[[
    Pass ladder: tiered multiplier passes (x2, x4, x8 ... ) as DATA. Pure: loads under Lune.

    The module never holds a price. Prices live in Creator Hub and are read at runtime through the
    PriceLookup port (ADR 0024); the ladder only checks that the live base prices ascend with the
    tiers (`priceOrderProblems`), because a higher tier that costs less than a lower one is a
    config bug. Ownership comes from the server (passes the player owns), never from a client.

    Stacking:
    - "highest": only the best owned tier counts (default; a player who buys x4 after x2 gets x4).
    - "product": all owned tiers multiply; the result is clipped to `maxMultiplier`.
]]

export type Stacking = "highest" | "product"

export type Tier = {
    -- Name of an entry of Config.gamePasses.
    passName: string,
    multiplier: number,
}

export type PassLadderConfig = {
    -- Stable id of the ladder (a game may have one for income, one for luck...).
    id: string,
    stacking: Stacking,
    -- Hard ceiling of the resulting multiplier.
    maxMultiplier: number,
    -- Ascending by multiplier.
    tiers: { Tier },
}

local PassLadderModule = {}

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- One human-readable problem per invalid value (empty when valid). `knownPasses` is the set of
--- names in Config.gamePasses.
function PassLadderModule.validate(
    config: PassLadderConfig,
    knownPasses: { [string]: boolean }
): { string }
    local problems: { string } = {}
    local label = `passLadder "{config.id}"`
    if config.id == "" then
        table.insert(problems, "a pass ladder needs an id")
    end
    if #config.tiers == 0 then
        table.insert(problems, `{label} needs at least one tier`)
    end
    if not isFinite(config.maxMultiplier) or config.maxMultiplier <= 1 then
        table.insert(problems, `{label} maxMultiplier must be greater than 1`)
    end
    local seen: { [string]: boolean } = {}
    local previous = 1
    local product = 1
    for index, tier in config.tiers do
        if not isFinite(tier.multiplier) or tier.multiplier <= previous then
            table.insert(problems, `{label} tier {index} must have a multiplier above the previous`)
        else
            previous = tier.multiplier
            product *= tier.multiplier
        end
        if seen[tier.passName] then
            table.insert(problems, `{label} uses pass "{tier.passName}" twice`)
        end
        seen[tier.passName] = true
        if not knownPasses[tier.passName] then
            table.insert(problems, `{label} tier {index} names an unknown pass "{tier.passName}"`)
        end
    end
    if config.stacking == "highest" and previous > config.maxMultiplier then
        table.insert(problems, `{label} top tier is above maxMultiplier`)
    end
    return problems
end

--- The multiplier a player gets. `owns` answers for a pass name (server-side ownership).
function PassLadderModule.multiplier(
    config: PassLadderConfig,
    owns: (passName: string) -> boolean
): number
    local result = 1
    for _, tier in config.tiers do
        if owns(tier.passName) then
            if config.stacking == "highest" then
                result = math.max(result, tier.multiplier)
            else
                result *= tier.multiplier
            end
        end
    end
    return math.min(result, config.maxMultiplier)
end

--- The first tier above what the player owns (the upsell), or nil at the top.
function PassLadderModule.nextTier(
    config: PassLadderConfig,
    owns: (passName: string) -> boolean
): Tier?
    local best = 1
    for _, tier in config.tiers do
        if owns(tier.passName) and tier.multiplier > best then
            best = tier.multiplier
        end
    end
    for _, tier in config.tiers do
        if tier.multiplier > best and not owns(tier.passName) then
            return tier
        end
    end
    return nil
end

--- Problems when the live base prices do not ascend with the tiers. `basePriceOf` answers from
--- the PriceLookup port (nil when the quote failed: reported, not guessed).
function PassLadderModule.priceOrderProblems(
    config: PassLadderConfig,
    basePriceOf: (passName: string) -> number?
): { string }
    local problems: { string } = {}
    local previousPrice = 0
    for index, tier in config.tiers do
        local price = basePriceOf(tier.passName)
        if price == nil then
            table.insert(problems, `passLadder "{config.id}" tier {index} has no live price`)
        else
            if price <= previousPrice then
                table.insert(
                    problems,
                    `passLadder "{config.id}" tier {index} costs no more than the tier below`
                )
            end
            previousPrice = price
        end
    end
    return problems
end

return PassLadderModule
