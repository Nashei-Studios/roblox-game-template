--!strict
--[[
    Client-side toast logic (issue #29), pure: loads under Lune. It turns a server notification
    (kind + amount) into a toast from Config, queues it, and on every `tick` hides expired toasts
    and shows queued ones up to `maxVisible`. Drawing is behind the ToastRenderer port; the
    optional `playSound` callback is bound to the sound manager by the client entry point.
]]

local NotificationsConfig = require("./NotificationsConfig")
local ToastQueue = require("./ToastQueue")
local ToastRenderer = require("../../ports/ToastRenderer")

export type Deps = {
    config: NotificationsConfig.NotificationsConfig,
    renderer: ToastRenderer.ToastRenderer,
    -- Plays a sound effect by its Config name; nil when the client has no sound manager yet.
    playSound: ((name: string) -> ())?,
}

export type ToastController = {
    -- False when the kind is unknown (nothing is shown).
    receive: (self: ToastController, kind: string, amount: number, now: number) -> boolean,
    tick: (self: ToastController, now: number) -> (),
}

type Visible = { id: number, expiresAt: number }

local ToastControllerModule = {}

function ToastControllerModule.new(deps: Deps): ToastController
    local queue = ToastQueue.new({
        maxQueue = deps.config.maxQueue,
        dedupeSeconds = deps.config.dedupeSeconds,
        maxWaitSeconds = deps.config.maxWaitSeconds,
    })
    local visible: { Visible } = {}
    local nextId = 1

    local controller: ToastController
    controller = {
        receive = function(
            _self: ToastController,
            kind: string,
            amount: number,
            now: number
        ): boolean
            local entry = deps.config.kinds[kind]
            if entry == nil then
                return false
            end
            queue:push({
                kind = kind,
                text = (string.gsub(entry.text, "{amount}", tostring(amount))),
                style = entry.style,
                durationSeconds = entry.durationSeconds,
                sound = entry.sound,
                enqueuedAt = now,
            })
            controller:tick(now)
            return true
        end,
        tick = function(_self: ToastController, now: number)
            for index = #visible, 1, -1 do
                local shown = visible[index]
                if now >= shown.expiresAt then
                    deps.renderer:hide(shown.id)
                    table.remove(visible, index)
                end
            end
            while #visible < deps.config.maxVisible do
                local pending = queue:pop(now)
                if pending == nil then
                    return
                end
                local id = nextId
                nextId += 1
                table.insert(visible, { id = id, expiresAt = now + pending.durationSeconds })
                deps.renderer:show({
                    id = id,
                    kind = pending.kind,
                    text = pending.text,
                    style = pending.style,
                    durationSeconds = pending.durationSeconds,
                })
                local play = deps.playSound
                if play ~= nil and pending.sound ~= nil then
                    play(pending.sound)
                end
            end
        end,
    }
    return controller
end

return ToastControllerModule
