--!strict
--[[
    Port: the screen side of the menus. The client presenter src/client/presenters/ui/UiKit builds
    the instances from the tokens of Config.default.ui and implements it; a game, or a pack, can
    plug in another presenter behind the same type without changing MenuController (ADR 0022).
]]

export type UiPresenter = {
    -- Shows or hides a menu by id (a MenuConfig id).
    setVisible: (self: UiPresenter, menuId: string, visible: boolean) -> (),
    -- Sets a named text slot, for example "hud.coins".
    setText: (self: UiPresenter, slot: string, text: string) -> (),
}

return {}
