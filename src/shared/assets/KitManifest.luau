--!strict
--[[
    Pure validation of the third-party kit manifest (ADR 0027, ADR 0067). No engine calls, loads under Lune.
    A failure is a plain sentence naming the kit, so a CI log says what to fix.
]]

export type Ships = "yes" | "no" | "private-upload-only"

export type Kit = {
    slug: string,
    version: string?,
    ships: string,
    sha256: string?,
    license: string,
    libraryPath: string,
    rojoPath: string?,
}

local ROJO_ROOT = "assets/kits/"

local KitManifest = {}

local function isSlug(value: string): boolean
    return string.match(value, "^[a-z0-9]+[a-z0-9%.%-]*$") ~= nil
end

-- Relative to the library root: no drive, no leading slash, no parent segment.
local function isRelative(value: string): boolean
    if value == "" or string.match(value, "^%a:") or string.match(value, "^[/]") then
        return false
    end
    for segment in string.gmatch(value, "[^/]+") do
        if segment == ".." then
            return false
        end
    end
    return true
end

local function isSha256(value: string): boolean
    return #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

function KitManifest.validate(kits: { Kit }): { string }
    local failures: { string } = {}
    local seen: { [string]: boolean } = {}
    for _, kit in kits do
        local name = kit.slug
        if not isSlug(kit.slug) then
            table.insert(failures, `{name}: slug must be lowercase kebab-case`)
        end
        if seen[kit.slug] then
            table.insert(failures, `{name}: duplicate slug`)
        end
        seen[kit.slug] = true
        if kit.ships ~= "yes" and kit.ships ~= "no" and kit.ships ~= "private-upload-only" then
            table.insert(failures, `{name}: ships must be yes, no or private-upload-only`)
        end
        if kit.sha256 ~= nil and not isSha256(kit.sha256) then
            table.insert(failures, `{name}: sha256 must be 64 lowercase hex characters`)
        end
        if kit.license == "" then
            table.insert(failures, `{name}: license must state the terms or "unknown"`)
        end
        if not isRelative(kit.libraryPath) then
            table.insert(
                failures,
                `{name}: libraryPath must be relative to the kit library (ADR 0067)`
            )
        end
        if kit.rojoPath ~= nil then
            if kit.ships == "no" then
                table.insert(failures, `{name}: a kit that does not ship has no rojoPath`)
            end
            if kit.rojoPath ~= ROJO_ROOT .. kit.slug then
                table.insert(failures, `{name}: rojoPath must be {ROJO_ROOT}{kit.slug}`)
            end
        elseif kit.ships == "yes" then
            table.insert(failures, `{name}: a kit that ships needs a rojoPath`)
        end
    end
    return failures
end

return KitManifest
