--!strict
--[[
    Luau CLI entry point: `luau --coverage scripts/test_luau.luau` (see scripts/coverage.ps1).
    Uses no Lune API; a failure raises an error so the CLI exits non-zero.
]]

local suites = require("./suites")

local _, failed = suites.run()
if failed > 0 then
    error(`{failed} test(s) failed`)
end
