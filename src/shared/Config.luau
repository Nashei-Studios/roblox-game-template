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

-- What a developer product delivers (applied by features/monetization/ProductGrants).
export type ProductGrant = { kind: "coins", amount: number }

export type DeveloperProductConfig = {
    name: string,
    id: number?,
    grant: ProductGrant,
}

export type GameConfig = {
    gameName: string,
    -- Seconds after which ProfileStore assumes a silent server is dead (ASSUME_DEAD).
    sessionLockTimeoutSeconds: number,
    -- Seconds between ProfileStore autosaves (AUTO_SAVE_PERIOD).
    autosaveIntervalSeconds: number,
    -- Receipt ledger window: how many recent PurchaseIds each profile remembers (ADR 0016).
    purchaseLedgerSize: number,
    -- Seconds a receipt waits for its save to be confirmed before Roblox is told to retry.
    saveConfirmTimeoutSeconds: number,
    gamePasses: { ProductConfig },
    developerProducts: { DeveloperProductConfig },
}

local Config = {}

Config.default = {
    gameName = "My Game", -- TODO(victor): set the game name
    sessionLockTimeoutSeconds = 1800,
    autosaveIntervalSeconds = 120,
    purchaseLedgerSize = 50,
    saveConfirmTimeoutSeconds = 30,
    gamePasses = {
        { name = "VIP", id = nil }, -- TODO(victor): set id
    },
    developerProducts = {
        { name = "Coins100", id = nil, grant = { kind = "coins", amount = 100 } }, -- TODO(victor): set id
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
    if config.purchaseLedgerSize < 1 or config.purchaseLedgerSize % 1 ~= 0 then
        table.insert(problems, "purchaseLedgerSize must be a positive integer")
    end
    if config.saveConfirmTimeoutSeconds <= 0 then
        table.insert(problems, "saveConfirmTimeoutSeconds must be positive")
    end
    for _, pass in config.gamePasses do
        if pass.id == nil then
            table.insert(problems, `game pass "{pass.name}" has no id`)
        end
    end
    local seenNames: { [string]: boolean } = {}
    for _, product in config.developerProducts do
        if product.id == nil then
            table.insert(problems, `developer product "{product.name}" has no id`)
        end
        if seenNames[product.name] then
            table.insert(problems, `developer product "{product.name}" is declared twice`)
        end
        seenNames[product.name] = true
        local grant = product.grant
        if grant.kind ~= "coins" then
            table.insert(problems, `developer product "{product.name}" has an unknown grant kind`)
        elseif grant.amount ~= grant.amount or grant.amount <= 0 or grant.amount % 1 ~= 0 then
            table.insert(
                problems,
                `developer product "{product.name}" grants an invalid amount (must be a positive integer)`
            )
        end
    end
    return problems
end

--- Finds a developer product by its Roblox id, or nil when unknown.
function Config.findProductById(config: GameConfig, productId: number): DeveloperProductConfig?
    for _, product in config.developerProducts do
        if product.id == productId then
            return product
        end
    end
    return nil
end

--- Grant declarations keyed by product name, the input of ProductGrants.new.
function Config.grantsByName(config: GameConfig): { [string]: ProductGrant }
    local grants: { [string]: ProductGrant } = {}
    for _, product in config.developerProducts do
        grants[product.name] = product.grant
    end
    return grants
end

return Config
