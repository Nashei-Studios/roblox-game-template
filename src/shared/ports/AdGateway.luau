--!strict
--[[
    Port: plays a rewarded video ad for a player (ADR 0022). The gateway only SHOWS the ad.
    It never grants anything: the reward is a developer product delivered by the Monetization
    receipt path (ProcessReceipt, granted only after a confirmed save, ADR 0016).
    A pack adapter can implement this type later without changing callers.
]]

-- How the ad ended. Anything but "completed" means no reward was earned and the UI simply
-- hides the button again (no error is shown to the player).
export type ShowOutcome =
    "completed"
    | "notReady"
    | "alreadyShowing"
    | "interrupted"
    | "insufficientMemory"
    | "failed"

export type ShowRequest = {
    -- Creator Hub ad placement id; nil reports under the default placement.
    placementId: number?,
    -- Roblox id of the reward developer product.
    rewardProductId: number,
}

export type ShowError = { kind: "show_failed", message: string }

export type AdGateway = {
    show: (
        self: AdGateway,
        userId: number,
        request: ShowRequest
    ) -> { ok: true, value: ShowOutcome } | { ok: false, error: ShowError },
}

return {}
