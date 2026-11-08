--!strict
--[[
    Client presenter of clip moments: runs the plan of features/clipmoment/MomentDirector.
    CaptureService is a client service (docs: CaptureService, read 2026-11-08), so everything
    here runs on the client; the server tells the client that a moment happened through a remote
    the game owns. Slow motion has no engine time scale on the client, so it is a hook the game
    implements (for example by scaling its own tweens and animation speed). The sting is a hook
    into the music director / sound manager. Touches the engine: excluded from the coverage gate.
]]

local CaptureService = game:GetService("CaptureService")

export type Step = { at: number, action: string, name: string?, value: number? }
export type Plan = { momentId: string, kind: string, steps: { Step }, dropped: { string } }

export type Hooks = {
    playSting: (name: string) -> (),
    -- Camera kick, intensity 0..1. The game shakes its own camera rig.
    cameraKick: (intensity: number) -> (),
    -- Scale in (0, 1) while a slow-motion window is open, 1 when it closes.
    setTimeScale: (scale: number) -> (),
    -- Launch data carried by the share invite link (for example the moment id).
    launchData: (momentId: string) -> string,
}

local ClipMomentPresenter = {}

local function requestShare(momentId: string, hooks: Hooks, contentId: string)
    local ok, failure = pcall(function()
        CaptureService:PromptShareCapture(
            Content.fromUri(contentId),
            hooks.launchData(momentId),
            function() end,
            function() end
        )
    end)
    if not ok then
        warn(`Share prompt failed: {failure}`)
    end
end

--- Schedules every step of the plan. A capture that never becomes ready simply skips the prompt.
function ClipMomentPresenter.run(plan: Plan, hooks: Hooks)
    local capturedId: string? = nil
    for _, step in plan.steps do
        task.delay(step.at, function()
            if step.action == "sting" and step.name ~= nil then
                hooks.playSting(step.name)
            elseif step.action == "camera_kick" and step.value ~= nil then
                hooks.cameraKick(step.value)
            elseif step.action == "slow_mo_start" and step.value ~= nil then
                hooks.setTimeScale(step.value)
            elseif step.action == "slow_mo_end" then
                hooks.setTimeScale(1)
            elseif step.action == "capture" then
                local ok, failure = pcall(function()
                    CaptureService:CaptureScreenshot(function(contentId: string)
                        capturedId = contentId
                    end)
                end)
                if not ok then
                    warn(`Capture failed: {failure}`)
                end
            elseif step.action == "share_prompt" then
                local id = capturedId
                if id ~= nil then
                    requestShare(plan.momentId, hooks, id)
                end
            end
        end)
    end
end

return ClipMomentPresenter
