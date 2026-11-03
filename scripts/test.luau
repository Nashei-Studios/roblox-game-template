--!strict
--[[
    Lune entry point: `lune run scripts/test`. The suites live in scripts/suites.luau (neutral).
]]

local process = require("@lune/process")

local suites = require("./suites")

local _, failed = suites.run()
if failed > 0 then
    process.exit(1)
end
