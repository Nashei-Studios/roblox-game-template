--!strict
--[[
    Typed config of notifications and toasts, and its validation. Pure: loads under Lune.
    Texts, styles, durations and the sound of every toast live in Config.default.notifications.
]]

export type ToastStyle = "info" | "success" | "warning" | "error"

export type KindConfig = {
    -- Shown text; "{amount}" is replaced by the number the server sent.
    text: string,
    style: ToastStyle,
    durationSeconds: number,
    -- Name of an entry of Config.default.sound.sfx, or nil for silence.
    sound: string?,
}

export type NotificationsConfig = {
    -- Toasts waiting for a free slot; the oldest are dropped past this.
    maxQueue: number,
    -- Toasts on screen at once.
    maxVisible: number,
    -- A toast with the same kind and text within this many seconds of the last is dropped.
    dedupeSeconds: number,
    -- A queued toast older than this is dropped instead of shown late.
    maxWaitSeconds: number,
    kinds: { [string]: KindConfig },
}

local NotificationsConfigModule = {}

-- Kinds the engagement modules emit; Config must declare all of them. They mirror the
-- NotificationKind enum of net/schema.zap (keep both in sync).
NotificationsConfigModule.REQUIRED_KINDS = {
    "code_redeemed",
    "code_invalid",
    "code_expired",
    "code_used",
    "code_cooldown",
    "daily_claimed",
    "daily_unavailable",
    "session_gift_claimed",
    "session_gift_unavailable",
    "community_reward_claimed",
    "community_not_member",
} :: { string }

local STYLES: { [string]: boolean } = { info = true, success = true, warning = true, error = true }

local function isPositive(value: number): boolean
    return value == value and value > 0 and value ~= math.huge
end

--- One problem per invalid value. `sfxNames` is the set of declared sound effect names.
function NotificationsConfigModule.validate(
    config: NotificationsConfig,
    sfxNames: { [string]: boolean }
): { string }
    local problems: { string } = {}
    if not isPositive(config.maxQueue) or config.maxQueue % 1 ~= 0 then
        table.insert(problems, "notifications.maxQueue must be a positive integer")
    end
    if not isPositive(config.maxVisible) or config.maxVisible % 1 ~= 0 then
        table.insert(problems, "notifications.maxVisible must be a positive integer")
    end
    if config.dedupeSeconds ~= config.dedupeSeconds or config.dedupeSeconds < 0 then
        table.insert(problems, "notifications.dedupeSeconds must be zero or positive")
    end
    if not isPositive(config.maxWaitSeconds) then
        table.insert(problems, "notifications.maxWaitSeconds must be positive")
    end
    for _, kind in NotificationsConfigModule.REQUIRED_KINDS do
        if config.kinds[kind] == nil then
            table.insert(problems, `notifications.kinds is missing "{kind}"`)
        end
    end
    for name, kind in config.kinds do
        if kind.text == "" then
            table.insert(problems, `notification "{name}" has no text`)
        end
        if not STYLES[kind.style] then
            table.insert(problems, `notification "{name}" has an unknown style`)
        end
        if not isPositive(kind.durationSeconds) then
            table.insert(problems, `notification "{name}" needs a positive durationSeconds`)
        end
        if kind.sound ~= nil and not sfxNames[kind.sound] then
            table.insert(problems, `notification "{name}" uses an undeclared sound "{kind.sound}"`)
        end
    end
    return problems
end

return NotificationsConfigModule
