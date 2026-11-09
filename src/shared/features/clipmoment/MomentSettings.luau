--!strict
--[[
    The player's opt-outs for clip moments and the routing of a plan (ADR 0051). Pure: loads
    under Lune; persistence is injected. Three toggles, all on by default:
      effects        camera kick and slow motion
      sharePrompt    the share prompt after a moment
      autoCapture    the screenshot taken after a moment
    A prompt needs a capture, so the prompt is dropped when either of the two is off. The
    toggles grant nothing: nothing in the game may reward a share or a capture.
]]

local MomentDirector = require("./MomentDirector")

export type Toggles = { effects: boolean, sharePrompt: boolean, autoCapture: boolean }

export type Row = {
    -- Key of the toggle (`effects`, `sharePrompt`, `autoCapture`).
    key: string,
    label: string,
    description: string,
    default: boolean,
}

export type Deps = {
    -- Reads the saved toggles; nil when nothing was saved. May return a partial table.
    load: (() -> { [string]: unknown }?)?,
    -- Saves the toggles; returns false when it could not.
    save: ((toggles: Toggles) -> boolean)?,
    onError: (message: string) -> (),
}

export type Store = {
    get: (self: Store) -> Toggles,
    set: (self: Store, key: string, value: boolean) -> boolean,
    -- The director settings, read fresh at every moment (pass `function() return store:director() end`).
    director: (self: Store) -> MomentDirector.Settings,
}

local MomentSettings = {}

MomentSettings.KEYS = { "effects", "sharePrompt", "autoCapture" }

--- The rows a Settings menu draws, in order. Wording is neutral; a game may relabel them.
function MomentSettings.rows(): { Row }
    return {
        {
            key = "effects",
            label = "Moment effects",
            description = "Camera shake and slow motion on big moments",
            default = true,
        },
        {
            key = "autoCapture",
            label = "Capture moments",
            description = "Take a screenshot right after a big moment",
            default = true,
        },
        {
            key = "sharePrompt",
            label = "Share prompt",
            description = "Offer to share the screenshot (you can always skip it)",
            default = true,
        },
    }
end

function MomentSettings.defaults(): Toggles
    return { effects = true, sharePrompt = true, autoCapture = true }
end

--- The director settings from the toggles: a prompt needs a capture.
function MomentSettings.resolve(toggles: Toggles): MomentDirector.Settings
    return {
        effects = toggles.effects,
        sharePrompt = toggles.sharePrompt and toggles.autoCapture,
    }
end

export type Routed = {
    -- Steps the game runs itself (sting, camera, slow motion).
    local_: { MomentDirector.Step },
    -- Steps for the capture presenter (capture, share prompt).
    capture: { MomentDirector.Step },
}

--- Splits a plan so the game keeps its own beats and hands only the capture steps to the
--- capture presenter. Order inside each list is the plan order.
function MomentSettings.route(plan: MomentDirector.Plan): Routed
    local routed: Routed = { local_ = {}, capture = {} }
    for _, step in plan.steps do
        if step.action == "capture" or step.action == "share_prompt" then
            table.insert(routed.capture, step)
        else
            table.insert(routed.local_, step)
        end
    end
    return routed
end

-- Writes one named toggle; false when the key is not a toggle.
local function assign(toggles: Toggles, key: string, value: boolean): boolean
    if key == "effects" then
        toggles.effects = value
    elseif key == "sharePrompt" then
        toggles.sharePrompt = value
    elseif key == "autoCapture" then
        toggles.autoCapture = value
    else
        return false
    end
    return true
end

function MomentSettings.new(deps: Deps): Store
    local toggles = MomentSettings.defaults()
    local loadFn = deps.load
    if loadFn ~= nil then
        local saved = loadFn()
        if saved ~= nil then
            for _, key in MomentSettings.KEYS do
                local value = saved[key]
                -- Foreign data: only a real boolean replaces the default.
                if type(value) == "boolean" then
                    assign(toggles, key, value)
                end
            end
        end
    end

    local store: Store = {
        get = function(_self: Store): Toggles
            return {
                effects = toggles.effects,
                sharePrompt = toggles.sharePrompt,
                autoCapture = toggles.autoCapture,
            }
        end,
        set = function(_self: Store, key: string, value: boolean): boolean
            if not assign(toggles, key, value) then
                deps.onError(`unknown moment setting "{key}"`)
                return false
            end
            local saveFn = deps.save
            if saveFn ~= nil and not saveFn(toggles) then
                deps.onError(`moment setting "{key}" could not be saved`)
                return false
            end
            return true
        end,
        director = function(_self: Store): MomentDirector.Settings
            return MomentSettings.resolve(toggles)
        end,
    }
    return store
end

return MomentSettings
