--!strict
--[[
    Adapter: AdGateway over AdService:CreateAdRewardFromDevProductId and
    AdService:ShowRewardedVideoAdAsync (server-only; the availability check
    GetAdAvailabilityNowAsync is client-only and lives in the client script that owns the button).
    The engine is injected (ADR 0009). `ShowRewardedVideoAdAsync` is wired in Main.server to
    return the NAME of the Enum.ShowAdResult item, so this file needs no Enum. The result is
    never used to grant anything (the docs say to grant from ProcessReceipt).
]]

-- Structurally identical to ports/AdGateway.luau (local so this file loads under Lune).
type ShowOutcome =
    "completed"
    | "notReady"
    | "alreadyShowing"
    | "interrupted"
    | "insufficientMemory"
    | "failed"
type ShowRequest = { placementId: number?, rewardProductId: number }
type ShowError = { kind: "show_failed", message: string }
type AdGateway = {
    show: (
        self: AdGateway,
        userId: number,
        request: ShowRequest
    ) -> { ok: true, value: ShowOutcome } | { ok: false, error: ShowError },
}

export type AdServiceLike<P, R> = {
    CreateAdRewardFromDevProductId: (self: unknown, productId: number) -> R,
    -- Returns the Enum.ShowAdResult item name (for example "ShowCompleted").
    ShowRewardedVideoAdAsync: (
        self: unknown,
        player: P,
        reward: R,
        placementId: number?
    ) -> string,
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P, R> = {
    adService: AdServiceLike<P, R>,
    players: PlayersLike<P>,
}

local OUTCOME_BY_RESULT: { [string]: ShowOutcome } = {
    ShowCompleted = "completed",
    AdNotReady = "notReady",
    AdAlreadyShowing = "alreadyShowing",
    ShowInterrupted = "interrupted",
    InsufficientMemory = "insufficientMemory",
    InternalError = "failed",
}

local RobloxAdService = {}

function RobloxAdService.new<P, R>(deps: Deps<P, R>): AdGateway
    local gateway: AdGateway = {
        show = function(_self: AdGateway, userId: number, request: ShowRequest)
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return {
                    ok = false,
                    error = { kind = "show_failed", message = "player is not in the server" },
                }
            end
            local shown, resultName = pcall(function(): string
                local reward =
                    deps.adService:CreateAdRewardFromDevProductId(request.rewardProductId)
                return deps.adService:ShowRewardedVideoAdAsync(player, reward, request.placementId)
            end)
            if not shown then
                return {
                    ok = false,
                    error = {
                        kind = "show_failed",
                        message = `ShowRewardedVideoAdAsync failed: {tostring(resultName)}`,
                    },
                }
            end
            return { ok = true, value = OUTCOME_BY_RESULT[resultName] or "failed" }
        end,
    }
    return gateway
end

return RobloxAdService
