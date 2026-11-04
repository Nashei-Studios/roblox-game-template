--!strict
--[[
    Client presenter: the ToastRenderer port over StarterGui:SetCore("SendNotification"), the
    built-in debug fallback (issue #29). A game ships its own Studio-built toast UI as another
    ToastRenderer; this one keeps the template playable before that exists. It touches the engine,
    so it is excluded from the line-coverage gate and kept this thin on purpose.
    Text comes from Config through ToastController; nothing is hardcoded here.
]]

local StarterGui = game:GetService("StarterGui")

-- Structurally identical to ports/ToastRenderer.luau (kept local: this file loads in-engine only).
type Toast = {
    id: number,
    kind: string,
    text: string,
    style: string,
    durationSeconds: number,
}

type ToastRenderer = {
    show: (self: ToastRenderer, toast: Toast) -> (),
    hide: (self: ToastRenderer, toastId: number) -> (),
}

local SetCoreToastRenderer = {}

function SetCoreToastRenderer.new(): ToastRenderer
    local renderer: ToastRenderer = {
        show = function(_self: ToastRenderer, toast: Toast)
            local sent, failure = pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = toast.kind,
                    Text = toast.text,
                    Duration = toast.durationSeconds,
                })
            end)
            if not sent then
                -- SetCore can fail while the core scripts register; the toast is lost, not the game.
                warn(`SendNotification failed for "{toast.kind}": {failure}`)
            end
        end,
        hide = function(_self: ToastRenderer, _toastId: number)
            -- SendNotification removes itself after its Duration.
        end,
    }
    return renderer
end

return SetCoreToastRenderer
