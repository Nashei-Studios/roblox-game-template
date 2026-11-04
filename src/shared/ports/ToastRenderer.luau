--!strict
--[[
    Port: the screen side of a toast. The client presenter
    src/client/presenters/SetCoreToastRenderer (debug fallback over StarterGui:SetCore)
    implements it; a game replaces it with its own Studio-built UI presenter.
]]

export type Toast = {
    id: number,
    kind: string,
    text: string,
    style: string,
    durationSeconds: number,
}

export type ToastRenderer = {
    show: (self: ToastRenderer, toast: Toast) -> (),
    hide: (self: ToastRenderer, toastId: number) -> (),
}

return {}
