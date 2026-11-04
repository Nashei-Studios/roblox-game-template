--!strict
--[[
    Grants and revokes subscription benefits from the LIVE status (ADR 0022). Pure: loads under
    Lune; every external fact comes through the SubscriptionPort.

    Rules:
    - Saved data is never read: the first reconcile of a player always calls `apply`, with
      `active = false` for non-subscribers, so a benefit persisted by an older session is revoked.
    - A lookup failure keeps the previous state and is returned to the caller (who logs it); it
      is never treated as "not subscribed".
    - A legacy pass owner keeps the benefit (the pass is checked first and wins).
    - `apply` is called only when the state changes (or on the first answer).
]]

local Config = require("../../Config")
local SubscriptionPort = require("../../ports/SubscriptionPort")

export type Entry = {
    name: string,
    subscriptionId: string,
    benefits: { string },
    legacyPassId: number?,
}

export type Failure = { subscription: string, message: string }

export type Deps = {
    entries: { Entry },
    port: SubscriptionPort.SubscriptionPort,
    -- Grants (active = true) or revokes (active = false) the entry's benefits for the player.
    apply: (userId: number, entry: Entry, active: boolean) -> (),
}

export type BenefitReconciler = {
    -- Re-reads every subscription for the player (join and periodic poll).
    reconcile: (self: BenefitReconciler, userId: number) -> { Failure },
    -- Re-reads the subscription named by a status-change event; unknown ids are ignored.
    onChanged: (self: BenefitReconciler, userId: number, subscriptionId: string) -> { Failure },
    isActive: (self: BenefitReconciler, userId: number, name: string) -> boolean,
    forget: (self: BenefitReconciler, userId: number) -> (),
}

local BenefitReconcilerModule = {}

--- Entries for every configured subscription that already has an id. Entries without an id are
--- left out (Config.validate reports them), so an unset id never reaches the platform.
function BenefitReconcilerModule.entriesFromConfig(config: Config.GameConfig): { Entry }
    local entries: { Entry } = {}
    local subscriptions: { Config.SubscriptionConfig } = config.subscriptions or {}
    for _, subscription in subscriptions do
        local subscriptionId = subscription.subscriptionId
        if subscriptionId ~= nil and subscriptionId ~= "" then
            local legacyPassId: number? = nil
            for _, pass in config.gamePasses do
                if pass.name == subscription.replacesPassName then
                    legacyPassId = pass.id
                end
            end
            table.insert(entries, {
                name = subscription.name,
                subscriptionId = subscriptionId,
                benefits = subscription.benefits,
                legacyPassId = legacyPassId,
            })
        end
    end
    return entries
end

function BenefitReconcilerModule.new(deps: Deps): BenefitReconciler
    -- userId -> subscription name -> last applied state.
    local states: { [number]: { [string]: boolean } } = {}

    local function refresh(userId: number, entry: Entry): Failure?
        local active = false
        if entry.legacyPassId ~= nil then
            local owned = deps.port:ownsPass(userId, entry.legacyPassId)
            if not owned.ok then
                return { subscription = entry.name, message = owned.error.message }
            end
            active = owned.value
        end
        if not active then
            local status = deps.port:statusOf(userId, entry.subscriptionId)
            if not status.ok then
                return { subscription = entry.name, message = status.error.message }
            end
            active = status.value.isSubscribed
        end
        local byName = states[userId]
        if byName == nil then
            byName = {}
            states[userId] = byName
        end
        if byName[entry.name] ~= active then
            byName[entry.name] = active
            deps.apply(userId, entry, active)
        end
        return nil
    end

    local reconciler: BenefitReconciler = {
        reconcile = function(_self: BenefitReconciler, userId: number): { Failure }
            local failures: { Failure } = {}
            for _, entry in deps.entries do
                local failure = refresh(userId, entry)
                if failure ~= nil then
                    table.insert(failures, failure)
                end
            end
            return failures
        end,
        onChanged = function(
            _self: BenefitReconciler,
            userId: number,
            subscriptionId: string
        ): { Failure }
            local failures: { Failure } = {}
            for _, entry in deps.entries do
                if entry.subscriptionId == subscriptionId then
                    local failure = refresh(userId, entry)
                    if failure ~= nil then
                        table.insert(failures, failure)
                    end
                end
            end
            return failures
        end,
        isActive = function(_self: BenefitReconciler, userId: number, name: string): boolean
            local byName = states[userId]
            return byName ~= nil and byName[name] == true
        end,
        forget = function(_self: BenefitReconciler, userId: number)
            states[userId] = nil
        end,
    }
    return reconciler
end

return BenefitReconcilerModule
