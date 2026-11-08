--!strict
--[[
    Toast host for the overlay layer, implementing the same `show`/`hide` shape as the
    ToastRenderer port (src/shared/ports/ToastRenderer): toasts stack at the top centre of the
    safe frame, never wider than the menu box, coloured by style from the palette. Read-only: a
    toast takes no input, so it can never block a tap. Queueing and durations stay in
    features/notifications (ToastController).
]]

local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local Stack = require(script.Parent.Stack)
local UiEnv = require(script.Parent.UiEnv)

export type ToastData = {
    id: number,
    kind: string,
    text: string,
    style: string,
    durationSeconds: number,
}

export type ToastHost = {
    show: (self: ToastHost, toast: ToastData) -> (),
    hide: (self: ToastHost, toastId: number) -> (),
}

local MAX_WIDTH = 480

local Toast = {}

function Toast.host(env: UiEnv.UiEnv, overlay: Instance): ToastHost
    local tokens = env.tokens
    local holder = Instance.new("Frame")
    holder.Name = "Toasts"
    holder.BackgroundTransparency = 1
    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.fromScale(0.5, 0)
    holder.Size = UDim2.fromScale(0.6, 0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
    limit.Parent = holder
    holder.Parent = overlay
    local stack = Stack.vertical(env, holder, { name = "Stack", gap = "sm" })

    local accents: { [string]: string } = {
        info = "focus",
        success = "success",
        warning = "warning",
        error = "danger",
    }
    local shown: { [number]: Frame? } = {}

    local host = {} :: ToastHost
    function host.show(_self: ToastHost, toast: ToastData)
        local card = Atoms.panel(stack, tokens, `Toast{toast.id}`, "surfaceRaised", "md")
        card.Size = UDim2.fromScale(1, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.LayoutOrder = toast.id
        -- Read-only: never takes a tap from what is underneath.
        card.Active = false
        Atoms.pad(card, tokens, "md")
        local label =
            Atoms.label(card, tokens, "Text", toast.text, "body", tokens.palette.textPrimary, 2)
        label.AutomaticSize = Enum.AutomaticSize.None
        local accent = Instance.new("UIStroke")
        accent.Thickness = 2
        accent.Color = Atoms.color(Atoms.hex(tokens, accents[toast.style] or "focus"))
        accent.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        accent.Parent = card
        shown[toast.id] = card
        DevGuard.verify(card, `Toast {toast.id}`)
    end
    function host.hide(_self: ToastHost, toastId: number)
        local card = shown[toastId]
        if card ~= nil then
            shown[toastId] = nil
            card:Destroy()
        end
    end
    return host
end

return Toast
