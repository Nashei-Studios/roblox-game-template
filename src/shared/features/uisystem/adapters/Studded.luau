--!strict
--[[
    Adapter of "Studded UI - Design Only" (RBLX Essentials, kits/rblx-essentials-studded-ui):
    14 menus and their buttons in a studded style, no scripts. Native-first: this is the default
    skin of the factory. Paths verified against the .rbxm on 2026-11-08 (scripts/ui-adapter-check).

    Licence (README of the kit): free or commercial use inside our own games, may be modified and
    shipped as part of a game; may NOT be sold, shared or redistributed as a pack, template or
    standalone download. So the .rbxm is copied into the git-ignored assets/kits/ and the pieces
    that ship are the ones a game extracts, never the template repository.

    The root of the tree is the ScreenGui named StuddedUI; paths start at its children.
]]

local KitAdapter = require("../KitAdapter")

local adapter: KitAdapter.KitAdapter = {
    id = "studded-ui",
    kitSlug = "rblx-essentials-studded-ui",
    license = "RBLX Essentials Studded UI: use and modify in own games; no redistribution as a pack",
    slots = {
        ["menu.shell"] = {
            path = "Templates/MenuTemplate",
            parts = {
                title = "Top.Title",
                close = "Top.CloseButton",
                body = "Container",
                -- Optional: the kit scrolling list, where menu rows go.
                rows = "Container.ScrollingContainer",
            },
            clear = { "Container.ScrollingContainer" },
        },
        ["menu.rowCard"] = {
            path = "Templates/MenuTemplate/Container/ScrollingContainer/Card",
            parts = { name = "Name", description = "Description", action = "Button" },
        },
        ["menu.rowToggle"] = {
            path = "Templates/MenuTemplate/Container/ScrollingContainer/Toggle",
            parts = { name = "Name", toggle = "ToggleButton" },
        },
        ["menu.rowUpgrade"] = {
            path = "Templates/MenuTemplate/Container/ScrollingContainer/Upgrade",
            parts = { action = "Button" },
        },
        ["hud.button"] = {
            path = "Templates/ButtonTemplate",
            parts = { icon = "Icon", badge = "Notification" },
        },
        ["tooltip.button"] = {
            path = "Tooltip/ButtonDetails",
            parts = { label = "ButtonName" },
        },
        ["effects.strip"] = {
            path = "Interactables/Effects",
            parts = {},
        },
    },
}

return adapter
