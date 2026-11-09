--!strict
--[[
    Client presenter of the reveal moment (ADR 0054): paints a `RevealMoment.Spec` over the UI
    overlay layer. A scrim that swallows input and dismisses on one tap, rotating light beams in
    the rarity color, the item icon (ItemIconView), the rarity label, the name, the odds line and
    a dismiss hint. Spacing, type and the touch floor come from the UI tokens (ADR 0045); every
    string arrives from the game. Beams turn as ONE group (one property write per frame) and
    sparks are a few short tweens, so the per-frame cost stays flat. The scrim is destroyed the
    moment the session ends, so input is blocked only while the reveal shows.
    Engine code: excluded from the coverage gate, kept thin. UNVERIFIED until a person checks it
    in Studio's Device Emulator (phone and PC sizes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local RevealMoment = require(Shared.features.reveal.RevealMoment)
local UiConfig = require(Shared.features.ui.UiConfig)
local Atoms = require(script.Parent.ui.system.Atoms)
local ItemIconView = require(script.Parent.ui.ItemIconView)
local UiEnv = require(script.Parent.ui.system.UiEnv)

export type Deps = {
    env: UiEnv.UiEnv,
    -- The kit theme ItemIconView reads.
    theme: UiConfig.Theme,
    -- The overlay layer of SafeAreaRoot (above menus and the HUD).
    parent: Instance,
    spec: RevealMoment.Spec,
    -- Strings from the game: the hint ("Tap to continue") and the lock tag text ItemIconView needs.
    dismissText: string,
    lockedText: string,
    -- Called once when the reveal ends, by tap or by time.
    onDone: () -> (),
}

local RevealMomentPresenter = {}

local BEAM_WIDTH_SCALE = 0.06
local BEAM_LENGTH_SCALE = 1.4
local SPARK_SECONDS = 0.7

--- Shows the reveal and returns a function that ends it early (idempotent).
function RevealMomentPresenter.show(deps: Deps): () -> ()
    local tokens = deps.env.tokens
    local spec = deps.spec
    local session = RevealMoment.session(spec)
    local connection: RBXScriptConnection? = nil
    local finished = false

    local scrim = Instance.new("TextButton")
    scrim.Name = "RevealScrim"
    scrim.Text = ""
    scrim.AutoButtonColor = false
    scrim.BorderSizePixel = 0
    scrim.BackgroundColor3 = Atoms.color(Atoms.hex(tokens, "scrim"))
    scrim.BackgroundTransparency = 0.25
    scrim.Size = UDim2.fromScale(1, 1)
    scrim.ZIndex = 50
    scrim.Parent = deps.parent

    local center = Instance.new("Frame")
    center.Name = "Center"
    center.BackgroundTransparency = 1
    center.Size = UDim2.fromScale(1, 1)
    center.ZIndex = 51
    center.Parent = scrim

    -- Beams: thin frames in one rotating group centered behind the icon.
    local beams = Instance.new("Frame")
    beams.Name = "Beams"
    beams.BackgroundTransparency = 1
    beams.AnchorPoint = Vector2.new(0.5, 0.5)
    beams.Position = UDim2.fromScale(0.5, 0.5)
    beams.Size = UDim2.fromScale(1, 1)
    beams.ZIndex = 51
    beams.Parent = center
    for index, angle in spec.beams.anglesDegrees do
        local beam = Instance.new("Frame")
        beam.Name = `Beam{index}`
        beam.BorderSizePixel = 0
        beam.AnchorPoint = Vector2.new(0.5, 1)
        beam.Position = UDim2.fromScale(0.5, 0.5)
        beam.Size = UDim2.fromScale(BEAM_WIDTH_SCALE, BEAM_LENGTH_SCALE / 2)
        beam.Rotation = angle
        beam.BackgroundColor3 = Atoms.color(spec.rarityHex)
        beam.BackgroundTransparency = 0.5
        beam.ZIndex = 51
        beam.Parent = beams
        local fade = Instance.new("UIGradient")
        fade.Rotation = 90
        fade.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        fade.Parent = beam
    end

    -- Column: icon, rarity label, name, odds, hint. Gaps are token keys.
    local column = Instance.new("Frame")
    column.Name = "Column"
    column.BackgroundTransparency = 1
    column.AnchorPoint = Vector2.new(0.5, 0.5)
    column.Position = UDim2.fromScale(0.5, 0.5)
    column.Size = UDim2.fromScale(0.6, 0)
    column.AutomaticSize = Enum.AutomaticSize.Y
    column.ZIndex = 52
    column.Parent = center
    local list = Atoms.list(column, tokens, "md", false)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local usable = deps.env.usable
    local iconSize = math.floor(math.min(usable.height * 0.4, usable.width * 0.4))
    local holder = Instance.new("Frame")
    holder.Name = "IconHolder"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(iconSize, iconSize)
    holder.LayoutOrder = 1
    holder.ZIndex = 52
    holder.Parent = column
    local view = ItemIconView.new({
        theme = deps.theme,
        parent = holder,
        name = "RevealIcon",
        lockedText = deps.lockedText,
    })
    view.root.Size = UDim2.fromScale(1, 1)
    view.apply(spec.icon)

    local function line(
        name: string,
        text: string,
        typeKey: string,
        colorHex: string,
        order: number
    )
        local label = Atoms.label(column, tokens, name, text, typeKey, colorHex)
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.LayoutOrder = order
        label.ZIndex = 52
    end
    line("Rarity", spec.rarityLabel, "title", spec.rarityHex, 2)
    line("Name", spec.name, "display", Atoms.hex(tokens, "textPrimary"), 3)
    if spec.oddsText ~= nil then
        line("Odds", spec.oddsText, "caption", Atoms.hex(tokens, "textMuted"), 4)
    end
    line("Hint", deps.dismissText, "caption", Atoms.hex(tokens, "textMuted"), 5)

    -- Pop-in of the icon: scale from 0.6 over a quarter of the reveal.
    local scale = Instance.new("UIScale")
    scale.Scale = 0.6
    scale.Parent = holder
    TweenService
        :Create(
            scale,
            TweenInfo.new(spec.durationSeconds / 4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        )
        :Play()

    local nextSpark = 0
    local function sparkle(now: number)
        if spec.particlesPerSecond <= 0 or now < nextSpark then
            return
        end
        nextSpark = now + 1 / spec.particlesPerSecond
        local spark = Instance.new("Frame")
        spark.Name = "Spark"
        spark.BorderSizePixel = 0
        spark.BackgroundColor3 = Atoms.color(spec.rarityHex)
        spark.AnchorPoint = Vector2.new(0.5, 0.5)
        spark.Size = UDim2.fromOffset(tokens.spacing.xs, tokens.spacing.xs)
        spark.Position = UDim2.fromScale(0.5, 0.5)
        spark.ZIndex = 51
        spark.Parent = center
        local angle = math.random() * math.pi * 2
        local radius = math.random() * 0.35 + 0.15
        TweenService:Create(
            spark,
            TweenInfo.new(SPARK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Position = UDim2.fromScale(
                    0.5 + math.cos(angle) * radius,
                    0.5 + math.sin(angle) * radius
                ),
                BackgroundTransparency = 1,
            }
        ):Play()
        task.delay(SPARK_SECONDS, function()
            spark:Destroy()
        end)
    end

    local function finish()
        if finished then
            return
        end
        finished = true
        if connection ~= nil then
            connection:Disconnect()
            connection = nil
        end
        view.destroy()
        scrim:Destroy()
        deps.onDone()
    end

    scrim.Activated:Connect(function()
        if session:dismiss(os.clock()) then
            finish()
        end
    end)

    session:start(os.clock())
    connection = RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if session:tick(now) == "done" then
            finish()
            return
        end
        beams.Rotation = spec.beams.spinDegreesPerSecond
            * session:progress(now)
            * spec.durationSeconds
        sparkle(now)
    end)

    return function()
        finish()
    end
end

return RevealMomentPresenter
