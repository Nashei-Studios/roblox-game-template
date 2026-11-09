--!strict
--[[
    Win-condition gate: `lune run scripts/win-condition [--strict]`.
    Reads Config.default.winCondition (the game declaration) and reports it against the checklist
    (docs/win-condition-checklist.md, vault ADR 0032).
    - A filled field that is wrong always exits 1.
    - A missing field exits 1 only with --strict (stage 1 closes strict). In the template and in a
      game before stage 1 the declaration is empty on purpose, so the default run reports it as
      pending and exits 0.
]]

local process = require("@lune/process")

local Config = require("../src/shared/Config")
local WinCondition = require("../src/shared/features/wincondition/WinCondition")

local strict = false
for _, argument in process.args do
    if argument == "--strict" then
        strict = true
    end
end

local declaration = Config.default.winCondition or WinCondition.empty()
local report = WinCondition.validate(declaration, nil)

for _, problem in report.problems do
    print(`FAIL  {problem}`)
end
for _, field in report.missing do
    print(`{if strict then "FAIL " else "PEND "} winCondition.{field} is not declared`)
end
print(
    `win-condition: {#report.problems} problems, {#report.missing} missing ({if strict
        then "strict"
        else "pending allowed"})`
)
if #report.problems > 0 or (strict and #report.missing > 0) then
    process.exit(1)
end
