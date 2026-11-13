--!strict
--[[
    Port: the screen side of the menus. The template ships no UI (ADR 0071): the game UI system
    implements this type and hands it to MenuController, which keeps the rules of which menu is
    open (ADR 0022).
]]

export type UiPresenter = {
    -- Shows or hides a menu by id (a MenuConfig id).
    setVisible: (self: UiPresenter, menuId: string, visible: boolean) -> (),
    -- Sets a named text slot, for example "hud.coins".
    setText: (self: UiPresenter, slot: string, text: string) -> (),
}

return {}
