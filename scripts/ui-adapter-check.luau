--!strict
--[[
    Verifies a kit adapter against the real kit file: `lune run scripts/ui-adapter-check <adapter> <kit.rbxm>`
    (adapter = studded). Exits 1 with one line per missing piece or part. No Studio. Used by the kit
    intake procedure (docs/ui-system.md) and run by hand when a kit is updated; the kit binary is
    not in git, so CI cannot run it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local KitAdapter = require("../src/shared/features/uisystem/KitAdapter")

local adapters: { [string]: KitAdapter.KitAdapter } = {
    studded = require("../src/shared/features/uisystem/adapters/Studded"),
}

local name = process.args[1]
local file = process.args[2]
if name == nil or file == nil or adapters[name] == nil then
    print("usage: lune run scripts/ui-adapter-check <studded> <kit.rbxm>")
    process.exit(2)
end
local adapter = adapters[name]

local own = KitAdapter.validate(adapter)
local roots = roblox.deserializeModel(fs.readFile(file))
local root = roots[1]

local function exists(path: string): boolean
    local current: any = root
    for part in string.gmatch(path, "[^/]+") do
        current = current:FindFirstChild(part)
        if current == nil then
            return false
        end
    end
    return true
end

local problems = own
for _, problem in KitAdapter.verify(adapter, exists) do
    table.insert(problems, problem)
end
for _, problem in problems do
    print(problem)
end
print(
    `ui-adapter-check: {adapter.id} {#problems} problems, uncovered slots: {#KitAdapter.uncovered(
        adapter
    )}`
)
if #problems > 0 then
    process.exit(1)
end
