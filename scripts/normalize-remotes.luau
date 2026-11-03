--!strict
--[[
    Lune entry point: `lune run scripts/normalize-remotes <file>...`. Rewrites each file with
    `EnumOrder.normalize` (see scripts/EnumOrder.luau). Called by scripts/generate-remotes.ps1.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local EnumOrder = require("./EnumOrder")

if #process.args == 0 then
    error("usage: lune run scripts/normalize-remotes <file>...")
end
for _, path in process.args do
    fs.writeFile(path, EnumOrder.normalize(fs.readFile(path)))
end
