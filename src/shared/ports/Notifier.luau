--!strict
--[[
    Port: tell one player something (a toast). Server side. The adapter
    src/server/adapters/RemoteNotifier sends it over the typed Notify remote; the client renders
    it with features/notifications/ToastController.
]]

export type NotifyError = "unknown_kind" | "player_gone"

export type Notifier = {
    -- `kind` is a key of Config.default.notifications.kinds; `amount` fills {amount} in its text.
    -- nil on success.
    notify: (self: Notifier, userId: number, kind: string, amount: number) -> NotifyError?,
}

return {}
