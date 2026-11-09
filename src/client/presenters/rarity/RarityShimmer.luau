--!strict
--[[
    One shared clock for every shimmer gradient (ADR 0046). A single Heartbeat connection moves
    all live gradients and disconnects when none is left, so the per-frame cost is one property
    write per live shimmer and zero when no card with a shimmer is on screen. At most
    `PerfBudget.clientFx.maxLiveShimmers` run; the rest stay on a static frame.
    Engine code: excluded from the coverage gate, kept thin. UNVERIFIED until a person checks it
    in Studio's Device Emulator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PerfBudget = require(ReplicatedStorage.Shared.perf.PerfBudget)

type Live = { gradient: UIGradient, period: number, startedAt: number }

local live: { [UIGradient]: Live } = {}
local liveCount = 0
local connection: RBXScriptConnection? = nil

local RarityShimmer = {}

local function step()
    local now = os.clock()
    for gradient, entry in live do
        -- Offset runs -1 to 1 across one period: the highlight band crosses the card once.
        local phase = ((now - entry.startedAt) % entry.period) / entry.period
        gradient.Offset = Vector2.new(phase * 2 - 1, 0)
    end
end

--- Starts animating `gradient`. Returns a stop function; stopping twice is harmless. Over the
--- budget the gradient is left on its static frame and the stop function does nothing.
function RarityShimmer.add(gradient: UIGradient, periodSeconds: number): () -> ()
    local cap = if PerfBudget.clientFx ~= nil then PerfBudget.clientFx.maxLiveShimmers else 0
    if liveCount >= cap or periodSeconds <= 0 then
        return function() end
    end
    live[gradient] = { gradient = gradient, period = periodSeconds, startedAt = os.clock() }
    liveCount += 1
    if connection == nil then
        connection = RunService.Heartbeat:Connect(step)
    end
    return function()
        if live[gradient] == nil then
            return
        end
        live[gradient] = nil
        liveCount -= 1
        if liveCount == 0 and connection ~= nil then
            connection:Disconnect()
            connection = nil
        end
    end
end

return RarityShimmer
