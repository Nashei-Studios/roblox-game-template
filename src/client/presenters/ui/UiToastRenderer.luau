--!strict
--[[
    Client presenter: the ToastRenderer port as a toast host inside the UI kit (replaces the
    SetCore debug fallback when the kit is mounted). Toasts stack at the top, colored by style
    from the palette; text and durations come from Config through ToastController. No hover or
    input is needed: a toast is read-only. It touches the engine, so it is excluded from the
    line-coverage gate and kept thin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage.Shared.features.ui.UiConfig)
local Widgets = require(script.Parent.Widgets)

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

local UiToastRenderer = {}

--- `host` is the kit's ScreenGui; `config` its ui config.
function UiToastRenderer.new(host: ScreenGui, config: UiConfig.UiConfig): ToastRenderer
    local theme = UiConfig.resolve(config.theme)
    local stack = Instance.new("Frame")
    stack.Name = "Toasts"
    stack.BackgroundTransparency = 1
    stack.AnchorPoint = Vector2.new(0.5, 0)
    stack.Position = UDim2.fromScale(0.5, 0)
    stack.Size = UDim2.fromScale(theme.panel.widthScale, 0)
    stack.AutomaticSize = Enum.AutomaticSize.Y
    stack.Parent = host
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(theme.panel.maxWidthPoints, math.huge)
    limit.Parent = stack
    Widgets.stack(stack, theme.spacing.sm)

    local shown: { [number]: Frame? } = {}
    local accents: { [string]: string } = {
        info = theme.palette.focus,
        success = theme.palette.success,
        warning = theme.palette.warning,
        error = theme.palette.danger,
    }

    local renderer: ToastRenderer = {
        show = function(_self: ToastRenderer, toast: Toast)
            local card = Widgets.panel(stack, theme, `Toast{toast.id}`, theme.palette.surfaceRaised)
            card.Size = UDim2.fromScale(1, 0)
            card.AutomaticSize = Enum.AutomaticSize.Y
            card.LayoutOrder = toast.id
            Widgets.pad(card, theme.spacing.md)
            local label =
                Widgets.label(card, theme, "Text", toast.text, "body", theme.palette.textPrimary)
            label.TextColor3 = Widgets.color(theme.palette.textPrimary)
            local stripe = Instance.new("UIStroke")
            stripe.Thickness = theme.strokeThickness * 2
            stripe.Color = Widgets.color(accents[toast.style] or theme.palette.focus)
            stripe.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stripe.Parent = card
            shown[toast.id] = card
        end,
        hide = function(_self: ToastRenderer, toastId: number)
            local card = shown[toastId]
            if card ~= nil then
                shown[toastId] = nil
                card:Destroy()
            end
        end,
    }
    return renderer
end

return UiToastRenderer
