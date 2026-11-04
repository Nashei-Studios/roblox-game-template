--!strict
--[[
    Typed game configuration. Pure: no Roblox services, loads under Lune.

    Ids start as nil on purpose. Never put a plausible-looking fake id here:
    `Config.validate` reports every missing id so a misconfigured game fails loudly.
]]

local CodesConfig = require("./features/codes/CodesConfig")
local NotificationsConfig = require("./features/notifications/NotificationsConfig")
local SoundConfig = require("./features/sound/SoundConfig")
local TimeRewardsConfig = require("./features/timerewards/TimeRewardsConfig")

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
    -- Dev performance probe (ADR 0019). Keep false in production; it also needs Studio to start.
    perfProbeEnabled: boolean?,
    gamePasses: { ProductConfig },
    developerProducts: { DeveloperProductConfig },
    -- Engagement modules (ADR 0025). Every value lives here; validate reports each problem.
    codes: CodesConfig.CodesConfig,
    timeRewards: TimeRewardsConfig.TimeRewardsConfig,
    notifications: NotificationsConfig.NotificationsConfig,
    sound: SoundConfig.SoundConfig,
}

local Config = {}

Config.default = {
    gameName = "My Game", -- TODO(victor): set the game name
    sessionLockTimeoutSeconds = 1800,
    autosaveIntervalSeconds = 120,
    purchaseLedgerSize = 50,
    saveConfirmTimeoutSeconds = 30,
    perfProbeEnabled = false,
    gamePasses = {
        { name = "VIP", id = nil }, -- TODO(victor): set id
    },
    developerProducts = {
        { name = "Coins100", id = nil, grant = { kind = "coins", amount = 100 } }, -- TODO(victor): set id
    },
    -- Engagement modules. Add a code, a reward, a toast or a sound HERE (see docs/architecture.md).
    codes = {
        maxCodeLength = 32,
        attemptCooldownSeconds = 1,
        failureThreshold = 5,
        entries = {}, -- { code = "WELCOME", reward = { kind = "coins", amount = 100 }, expiresAt = nil }
    },
    timeRewards = {
        graceHours = 6,
        daily = {
            { day = 1, reward = { kind = "coins", amount = 50 } },
            { day = 2, reward = { kind = "coins", amount = 75 } },
            { day = 3, reward = { kind = "coins", amount = 100 } },
        },
        sessionGifts = {
            { id = "gift5", afterMinutes = 5, reward = { kind = "coins", amount = 25 } },
            { id = "gift15", afterMinutes = 15, reward = { kind = "coins", amount = 60 } },
        },
    },
    notifications = {
        maxQueue = 8,
        maxVisible = 3,
        dedupeSeconds = 2,
        maxWaitSeconds = 20,
        kinds = {
            code_redeemed = {
                text = "Code redeemed: +{amount} coins",
                style = "success",
                durationSeconds = 4,
                sound = "reward",
            },
            code_invalid = { text = "That code is not valid", style = "error", durationSeconds = 3 },
            code_expired = {
                text = "That code has expired",
                style = "warning",
                durationSeconds = 3,
            },
            code_used = {
                text = "You already used that code",
                style = "warning",
                durationSeconds = 3,
            },
            code_cooldown = {
                text = "Wait a moment before trying another code",
                style = "info",
                durationSeconds = 3,
            },
            daily_claimed = {
                text = "Daily reward: +{amount} coins",
                style = "success",
                durationSeconds = 4,
                sound = "reward",
            },
            daily_unavailable = {
                text = "Your daily reward is not ready",
                style = "info",
                durationSeconds = 3,
            },
            session_gift_claimed = {
                text = "Gift: +{amount} coins",
                style = "success",
                durationSeconds = 4,
                sound = "reward",
            },
            session_gift_unavailable = {
                text = "That gift is not ready yet",
                style = "info",
                durationSeconds = 3,
            },
        },
    },
    sound = {
        sfx = {
            { name = "reward", assetId = nil, volume = 0.8 }, -- TODO(victor): set id
            { name = "click", assetId = nil, volume = 0.6 }, -- TODO(victor): set id
        },
        music = {
            { name = "lobby", assetId = nil, volume = 0.5 }, -- TODO(victor): set id
        },
        defaultVolumes = { music = 60, sfx = 80 },
        fadeSeconds = 1.5,
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
    for _, problem in CodesConfig.validate(config.codes) do
        table.insert(problems, problem)
    end
    for _, problem in TimeRewardsConfig.validate(config.timeRewards) do
        table.insert(problems, problem)
    end
    for _, problem in SoundConfig.validate(config.sound) do
        table.insert(problems, problem)
    end
    local sfxNames = SoundConfig.sfxNames(config.sound)
    for _, problem in NotificationsConfig.validate(config.notifications, sfxNames) do
        table.insert(problems, problem)
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

--- Finds a developer product by its name, or nil when unknown.
function Config.findProductByName(config: GameConfig, name: string): DeveloperProductConfig?
    for _, product in config.developerProducts do
        if product.name == name then
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
