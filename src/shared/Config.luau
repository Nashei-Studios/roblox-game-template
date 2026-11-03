--!strict
--[[
    Typed game configuration. Pure: no Roblox services, loads under Lune.

    Ids start as nil on purpose. Never put a plausible-looking fake id here:
    `Config.validate` reports every missing id so a misconfigured game fails loudly.
]]

export type ProductConfig = {
    name: string,
    id: number?,
}

export type GameConfig = {
    gameName: string,
    -- Seconds after which ProfileStore assumes a silent server is dead (ASSUME_DEAD).
    sessionLockTimeoutSeconds: number,
    -- Seconds between ProfileStore autosaves (AUTO_SAVE_PERIOD).
    autosaveIntervalSeconds: number,
    gamePasses: { ProductConfig },
    developerProducts: { ProductConfig },
}

local Config = {}

Config.default = {
    gameName = "My Game", -- TODO(victor): set the game name
    sessionLockTimeoutSeconds = 1800,
    autosaveIntervalSeconds = 120,
    gamePasses = {
        { name = "VIP", id = nil }, -- TODO(victor): set id
    },
    developerProducts = {
        { name = "Coins100", id = nil }, -- TODO(victor): set id
    },
} :: GameConfig

--- In-repo fallbacks for live-ops flags (Experience Configs override them; see features/flags).
Config.flagDefaults = {
    booleans = {
        purchasesEnabled = true,
    },
    numbers = {},
} :: { booleans: { [string]: boolean }, numbers: { [string]: number } }

--- Returns one human-readable problem per invalid or missing value (empty when valid).
function Config.validate(config: GameConfig): { string }
    local problems: { string } = {}
    if config.gameName == "" then
        table.insert(problems, "gameName is empty")
    end
    if config.sessionLockTimeoutSeconds <= 0 then
        table.insert(problems, "sessionLockTimeoutSeconds must be positive")
    end
    if config.autosaveIntervalSeconds <= 0 then
        table.insert(problems, "autosaveIntervalSeconds must be positive")
    end
    for _, pass in config.gamePasses do
        if pass.id == nil then
            table.insert(problems, `game pass "{pass.name}" has no id`)
        end
    end
    for _, product in config.developerProducts do
        if product.id == nil then
            table.insert(problems, `developer product "{product.name}" has no id`)
        end
    end
    return problems
end

--- Finds a developer product by its Roblox id, or nil when unknown.
function Config.findProductById(config: GameConfig, productId: number): ProductConfig?
    for _, product in config.developerProducts do
        if product.id == productId then
            return product
        end
    end
    return nil
end

return Config
