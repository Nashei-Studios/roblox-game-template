--!strict
--[[
    Which menu is open. Pure: loads under Lune; the screen side is the UiPresenter port.
    - The HUD is always visible and is not toggled.
    - Opening a modal menu closes the other modal menus (one screen at a time on a phone).
    - `back` closes whatever modal menu is open (gamepad B, Android back).
    - An id Config does not declare is refused with a typed error, never ignored.
]]

local UiConfig = require("./UiConfig")
local UiPresenter = require("../../ports/UiPresenter")

export type Result =
    { ok: true, value: boolean }
    | { ok: false, error: "unknown_menu" | "not_toggleable" }

export type MenuController = {
    open: (self: MenuController, menuId: string) -> Result,
    close: (self: MenuController, menuId: string) -> Result,
    toggle: (self: MenuController, menuId: string) -> Result,
    -- Closes the open modal menu, if any. True when something closed.
    back: (self: MenuController) -> boolean,
    isOpen: (self: MenuController, menuId: string) -> boolean,
}

export type Deps = {
    menus: { UiConfig.MenuConfig },
    presenter: UiPresenter.UiPresenter,
}

local MenuControllerModule = {}

function MenuControllerModule.new(deps: Deps): MenuController
    local byId: { [string]: UiConfig.MenuConfig } = {}
    local open: { [string]: boolean } = {}
    for _, menu in deps.menus do
        byId[menu.id] = menu
        if not menu.modal then
            open[menu.id] = true
            deps.presenter:setVisible(menu.id, true)
        else
            deps.presenter:setVisible(menu.id, false)
        end
    end

    local function setOpen(menu: UiConfig.MenuConfig, visible: boolean)
        if (open[menu.id] == true) == visible then
            return
        end
        open[menu.id] = visible
        deps.presenter:setVisible(menu.id, visible)
    end

    local controller: MenuController
    controller = {
        open = function(_self: MenuController, menuId: string): Result
            local menu = byId[menuId]
            if menu == nil then
                return { ok = false, error = "unknown_menu" }
            end
            if not menu.modal then
                return { ok = false, error = "not_toggleable" }
            end
            for _, other in deps.menus do
                if other.modal and other.id ~= menuId then
                    setOpen(other, false)
                end
            end
            setOpen(menu, true)
            return { ok = true, value = true }
        end,
        close = function(_self: MenuController, menuId: string): Result
            local menu = byId[menuId]
            if menu == nil then
                return { ok = false, error = "unknown_menu" }
            end
            if not menu.modal then
                return { ok = false, error = "not_toggleable" }
            end
            setOpen(menu, false)
            return { ok = true, value = false }
        end,
        toggle = function(self: MenuController, menuId: string): Result
            if open[menuId] == true then
                return self:close(menuId)
            end
            return self:open(menuId)
        end,
        back = function(_self: MenuController): boolean
            local closed = false
            for _, menu in deps.menus do
                if menu.modal and open[menu.id] == true then
                    setOpen(menu, false)
                    closed = true
                end
            end
            return closed
        end,
        isOpen = function(_self: MenuController, menuId: string): boolean
            return open[menuId] == true
        end,
    }
    return controller
end

return MenuControllerModule
