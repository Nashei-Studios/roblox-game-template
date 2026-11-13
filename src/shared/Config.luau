--!strict
--[[
    Typed game configuration. Pure: no Roblox services, loads under Lune.

    Ids start as nil on purpose. Never put a plausible-looking fake id here:
    `Config.validate` reports every missing id so a misconfigured game fails loudly.
]]

local CodesConfig = require("./features/codes/CodesConfig")
local Experiments = require("./features/experiments/Experiments")
local CommunityRewardConfig = require("./features/community-reward/CommunityRewardConfig")
local LeaderboardsConfig = require("./features/leaderboards/LeaderboardsConfig")
local NotificationsConfig = require("./features/notifications/NotificationsConfig")
local SoundConfig = require("./features/sound/SoundConfig")
local WinCondition = require("./features/wincondition/WinCondition")
local TimeRewardsConfig = require("./features/timerewards/TimeRewardsConfig")
local PerfBudget = require("./perf/PerfBudget")
local InspectView = require("./features/inspect/InspectView")
local ItemSlots = require("./features/itemslots/ItemSlots")
local AutoFeel = require("./features/autofeel/AutoFeel")
local PodiumConfig = require("./features/podium/PodiumConfig")
local RarityConfig = require("./features/rarity/RarityConfig")
local TierModelConfig = require("./features/tiermodels/TierModelConfig")

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

-- Experience subscription (Creator Hub > Monetization > Subscriptions). Ids are strings ("EXP-...").
-- `benefits` are game-defined perk names; the reconciler grants and revokes them by LIVE status.
export type SubscriptionConfig = {
    name: string,
    subscriptionId: string?,
    benefits: { string },
    -- Name of a gamePasses entry whose owners keep the benefit (legacy pass migrated to this sub).
    replacesPassName: string?,
}

-- Rewarded video ad slot. The reward is a developer product (by name), delivered by the
-- Monetization receipt path; `label` is the text shown on the opt-in button.
export type RewardedAdPlacementConfig = {
    name: string,
    -- Placement id from Creator Hub > Monetization > Ads > Placements. nil = default placement.
    placementId: number?,
    rewardProduct: string,
    label: string,
}

export type RewardedAdsConfig = {
    -- Keep false until the experience meets the eligibility conditions (docs: public, 2 thousand
    -- monthly unique visitors, ID-verified publisher with 2FA).
    enabled: boolean,
    -- Text that tells the player this is an ad (docs require a clear disclosure).
    disclosureLabel: string,
    -- Max completed ads per player per UTC day on one server.
    dailyCap: number,
    placements: { RewardedAdPlacementConfig },
}

export type PrivateServerSettingConfig = {
    name: string,
    min: number,
    max: number,
    default: number,
}

export type PrivateServersConfig = {
    enabled: boolean,
    -- EXPECTED monthly price in Robux. The real price is set in Creator Hub (code cannot set
    -- it): this value is only compared by the release checklist and is never shown in the UI.
    expectedMonthlyPrice: number,
    -- Retries after a TeleportInitFailed with a retryable result, and the wait between them.
    teleportRetries: number,
    teleportRetryDelaySeconds: number,
    settings: { PrivateServerSettingConfig },
}

-- Roblox Plus sign-up prompt (earns a bonus per new subscriber who signs up through the game).
export type PlusPromptConfig = {
    enabled: boolean,
    -- Named spots where the player can ask for the prompt (a button they press, never forced).
    placements: { string },
    -- Minimum seconds between two prompts to the same player.
    cooldownSeconds: number,
    maxPromptsPerSession: number,
}

-- In-game Robux transfers by Plus subscribers (the game earns a share of each transfer).
export type RobuxTransfersConfig = {
    enabled: boolean,
    minAmount: number,
    maxAmount: number,
}

export type GameConfig = {
    gameName: string,
    -- A/B experiments (ADR 0064): ids, variants, weights and an on/off switch each.
    experiments: Experiments.ExperimentsConfig?,
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
    -- Monetization surfaces (ADR 0022). Optional so a game can omit what it does not sell.
    subscriptions: { SubscriptionConfig }?,
    -- Seconds between live re-reads of subscription status (covers Store tab purchases).
    subscriptionPollSeconds: number?,
    rewardedAds: RewardedAdsConfig?,
    privateServers: PrivateServersConfig?,
    plusPrompt: PlusPromptConfig?,
    robuxTransfers: RobuxTransfersConfig?,
    -- Leaderboards and community join reward (issues #25, #36). Optional so a game can omit what
    -- it does not use; the defaults below ship both (the reward disabled). The template ships no
    -- UI config: the game's UI system owns its tokens, menus and texts (ADR 0071).
    -- Rarity ladder and effect tiers (ADR 0048); a game overrides the tiers and colors.
    rarity: RarityConfig.Config?,
    -- Hotbar of equipped items (ADR 0056): slot count and the keys that select each slot.
    itemSlots: ItemSlots.Config?,
    -- 3D item viewer (ADR 0060): rotation and zoom limits, input speeds and the keys that close it.
    inspect: InspectView.Config?,
    leaderboards: LeaderboardsConfig.LeaderboardsConfig?,
    -- 3D podium of a board's top three (ADR 0056); a game sets the board, words and animation.
    podium: PodiumConfig.PodiumConfig?,
    -- A distinct model, material and color set per tier (ADR 0057); a game lists its own tiers.
    tierModels: TierModelConfig.Config?,
    -- Feel of an automatic miner (ADR 0058); a game with no auto drill leaves it as is, unused.
    autoFeel: AutoFeel.AutoFeelConfig?,
    communityReward: CommunityRewardConfig.CommunityRewardConfig?,
    -- Win condition (vault ADR 0032): empty in the template, filled at stage 1 of a game.
    winCondition: WinCondition.WinConditionConfig?,
}

local Config = {}

-- Largest integer a Luau number holds exactly (2^53); ProductGrants rejects a larger grant, so a
-- product configured above it would charge Robux and never deliver.
Config.MAX_GRANT_COINS = 2 ^ 53

-- Platform bounds of one Robux transfer (docs: production/monetization/robux-transfers).
Config.ROBUX_TRANSFER_PLATFORM_MIN = 10
Config.ROBUX_TRANSFER_PLATFORM_MAX = 500

Config.default = {
    gameName = "My Game", -- TODO(victor): set the game name
    experiments = {
        funnelExperimentId = "onboarding",
        definitions = {
            -- Off by default: everyone gets the control until a game turns it on (vault 0038).
            {
                id = "onboarding",
                active = false,
                variants = {
                    { id = "control", weight = 1 },
                    { id = "variant_a", weight = 1 },
                },
            },
        },
    },
    -- Stage 1 of a game fills this (docs/win-condition-checklist.md); `lune run scripts/win-condition --strict`.
    winCondition = WinCondition.empty(),
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
            community_reward_claimed = {
                text = "Thanks for joining! +{amount} coins",
                style = "success",
                durationSeconds = 4,
                sound = "reward",
            },
            community_not_member = {
                text = "Join the community to get your reward",
                style = "info",
                durationSeconds = 4,
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
    -- Add { name, subscriptionId, benefits } entries once subscriptions exist in Creator Hub.
    subscriptions = {},
    subscriptionPollSeconds = 300,
    rewardedAds = {
        enabled = false, -- opt-in; turn on only when the experience is eligible
        disclosureLabel = "Watch an ad to get a reward",
        dailyCap = 5,
        -- Mirrors AdPlacementName in net/schema.zap. The reward must be a developer product.
        placements = {
            {
                name = "Default",
                placementId = nil, -- TODO(victor): Creator Hub placement id (optional)
                rewardProduct = "Coins100",
                label = "Watch an ad for 100 coins",
            },
        },
    },
    privateServers = {
        enabled = false,
        expectedMonthlyPrice = 100, -- expected only; the real price is set in Creator Hub
        teleportRetries = 2,
        teleportRetryDelaySeconds = 2,
        -- Mirrors PrivateServerSettingName in net/schema.zap.
        settings = {
            { name = "maxPlayers", min = 2, max = 12, default = 8 },
        },
    },
    plusPrompt = {
        enabled = false,
        -- Mirrors PlusPlacementName in net/schema.zap.
        placements = { "menu" },
        cooldownSeconds = 600,
        maxPromptsPerSession = 2,
    },
    robuxTransfers = {
        enabled = false,
        minAmount = 10,
        maxAmount = 500,
    },
    rarity = RarityConfig.default,
    itemSlots = ItemSlots.default,
    inspect = InspectView.default,
    leaderboards = {
        leaderstats = { "coins" },
        writeSeconds = 60,
        boards = {
            Coins = { stat = "coins", refreshSeconds = 120, size = 10, resetCycle = "never" },
            WeeklyCoins = { stat = "coins", refreshSeconds = 120, size = 10, resetCycle = "weekly" },
        },
    },
    podium = PodiumConfig.default,
    tierModels = TierModelConfig.default,
    autoFeel = AutoFeel.default,
    -- Off until Victor confirms the Community Standards allow rewarding a join (open [GAP]).
    communityReward = {
        enabled = false,
        communityId = nil, -- TODO(victor): set the community id
        reward = nil, -- TODO(victor): e.g. { kind = "coins", amount = 100 }
        recheckCooldownSeconds = 30,
        promptJoin = true,
    },
} :: GameConfig

--- In-repo fallbacks for live-ops flags (Experience Configs override them; see features/flags).
Config.flagDefaults = {
    booleans = {
        purchasesEnabled = true,
    },
    numbers = {},
} :: { booleans: { [string]: boolean }, numbers: { [string]: number } }

local function isPositiveInteger(value: number): boolean
    return value == value and value >= 1 and value % 1 == 0
end

local function validateSubscriptions(config: GameConfig, problems: { string })
    local subscriptions = config.subscriptions
    if subscriptions == nil or #subscriptions == 0 then
        return
    end
    local pollSeconds = config.subscriptionPollSeconds
    if pollSeconds == nil or pollSeconds <= 0 then
        table.insert(problems, "subscriptionPollSeconds must be positive when subscriptions exist")
    end
    local seen: { [string]: boolean } = {}
    for _, subscription in subscriptions do
        if subscription.subscriptionId == nil or subscription.subscriptionId == "" then
            table.insert(problems, `subscription "{subscription.name}" has no subscriptionId`)
        end
        if seen[subscription.name] then
            table.insert(problems, `subscription "{subscription.name}" is declared twice`)
        end
        seen[subscription.name] = true
        if #subscription.benefits == 0 then
            table.insert(problems, `subscription "{subscription.name}" has no benefits`)
        end
        local passName = subscription.replacesPassName
        if passName ~= nil then
            local found = false
            for _, pass in config.gamePasses do
                found = found or pass.name == passName
            end
            if not found then
                table.insert(
                    problems,
                    `subscription "{subscription.name}" replaces unknown game pass "{passName}"`
                )
            end
        end
    end
end

local function validateRewardedAds(config: GameConfig, problems: { string })
    local ads = config.rewardedAds
    if ads == nil or not ads.enabled then
        return
    end
    if ads.disclosureLabel == "" then
        table.insert(problems, "rewardedAds.disclosureLabel is empty")
    end
    if not isPositiveInteger(ads.dailyCap) then
        table.insert(problems, "rewardedAds.dailyCap must be a positive integer")
    end
    if #ads.placements == 0 then
        table.insert(problems, "rewardedAds is enabled but has no placements")
    end
    local seen: { [string]: boolean } = {}
    for _, placement in ads.placements do
        if seen[placement.name] then
            table.insert(problems, `rewarded ad placement "{placement.name}" is declared twice`)
        end
        seen[placement.name] = true
        if placement.label == "" then
            table.insert(problems, `rewarded ad placement "{placement.name}" has no label`)
        end
        if Config.findProductByName(config, placement.rewardProduct) == nil then
            table.insert(
                problems,
                `rewarded ad placement "{placement.name}" rewards unknown developer product "{placement.rewardProduct}"`
            )
        end
    end
end

local function validatePrivateServers(config: GameConfig, problems: { string })
    local servers = config.privateServers
    if servers == nil or not servers.enabled then
        return
    end
    if not isPositiveInteger(servers.expectedMonthlyPrice) then
        table.insert(problems, "privateServers.expectedMonthlyPrice must be a positive integer")
    end
    if servers.teleportRetries < 0 or servers.teleportRetries % 1 ~= 0 then
        table.insert(problems, "privateServers.teleportRetries must be a non-negative integer")
    end
    if servers.teleportRetryDelaySeconds <= 0 then
        table.insert(problems, "privateServers.teleportRetryDelaySeconds must be positive")
    end
    local seen: { [string]: boolean } = {}
    for _, setting in servers.settings do
        if seen[setting.name] then
            table.insert(problems, `private server setting "{setting.name}" is declared twice`)
        end
        seen[setting.name] = true
        local ordered = setting.min <= setting.default and setting.default <= setting.max
        if not ordered or setting.min % 1 ~= 0 or setting.max % 1 ~= 0 then
            table.insert(
                problems,
                `private server setting "{setting.name}" needs integer min <= default <= max`
            )
        end
    end
end

local function validatePlusPrompt(config: GameConfig, problems: { string })
    local plus = config.plusPrompt
    if plus == nil or not plus.enabled then
        return
    end
    if #plus.placements == 0 then
        table.insert(problems, "plusPrompt is enabled but has no placements")
    end
    local seen: { [string]: boolean } = {}
    for _, placement in plus.placements do
        if placement == "" or seen[placement] then
            table.insert(problems, "plusPrompt.placements must be unique non-empty names")
        end
        seen[placement] = true
    end
    if plus.cooldownSeconds <= 0 then
        table.insert(problems, "plusPrompt.cooldownSeconds must be positive")
    end
    if not isPositiveInteger(plus.maxPromptsPerSession) then
        table.insert(problems, "plusPrompt.maxPromptsPerSession must be a positive integer")
    end
end

local function validateRobuxTransfers(config: GameConfig, problems: { string })
    local transfers = config.robuxTransfers
    if transfers == nil or not transfers.enabled then
        return
    end
    local withinPlatform = transfers.minAmount >= Config.ROBUX_TRANSFER_PLATFORM_MIN
        and transfers.maxAmount <= Config.ROBUX_TRANSFER_PLATFORM_MAX
    if not withinPlatform or transfers.minAmount > transfers.maxAmount then
        table.insert(
            problems,
            `robuxTransfers amounts must satisfy {Config.ROBUX_TRANSFER_PLATFORM_MIN} <= minAmount <= maxAmount <= {Config.ROBUX_TRANSFER_PLATFORM_MAX}`
        )
    end
    if transfers.minAmount % 1 ~= 0 or transfers.maxAmount % 1 ~= 0 then
        table.insert(problems, "robuxTransfers amounts must be integers")
    end
end

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
    if config.experiments ~= nil then
        for _, problem in Experiments.validate(config.experiments) do
            table.insert(problems, problem)
        end
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
        elseif
            grant.amount ~= grant.amount
            or grant.amount <= 0
            or grant.amount % 1 ~= 0
            or grant.amount > Config.MAX_GRANT_COINS
        then
            table.insert(
                problems,
                `developer product "{product.name}" grants an invalid amount (must be a positive integer up to 2^53)`
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
    validateSubscriptions(config, problems)
    validateRewardedAds(config, problems)
    validatePrivateServers(config, problems)
    validatePlusPrompt(config, problems)
    validateRobuxTransfers(config, problems)
    if config.rarity ~= nil then
        local fx = PerfBudget.clientFx
        local cap = if fx ~= nil then fx.maxParticlesPerSecond else 0
        for _, problem in
            RarityConfig.validate(config.rarity, RarityConfig.referenceSurfaceHex, cap)
        do
            table.insert(problems, problem)
        end
    end
    if config.itemSlots ~= nil then
        for _, problem in ItemSlots.validate(config.itemSlots) do
            table.insert(problems, problem)
        end
    end
    if config.inspect ~= nil then
        for _, problem in InspectView.validate(config.inspect) do
            table.insert(problems, problem)
        end
    end
    if config.leaderboards ~= nil then
        for _, problem in LeaderboardsConfig.validate(config.leaderboards) do
            table.insert(problems, problem)
        end
    end
    if config.communityReward ~= nil then
        for _, problem in CommunityRewardConfig.validate(config.communityReward) do
            table.insert(problems, problem)
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
