--!strict
--[[
    Static UI audit gate (docs/ui-audit.md): `lune run scripts/ui-audit [report.json]`.
    Reads every committed assets/ui/**/*.rbxm (none in the template itself), applies StaticRules, then scans src/*.luau with SourceRules, and exits 1 with one line per
    finding (file, path, rule). No Studio. The runtime half is run in a playtest (RuntimeAudit).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Finding = require("../src/shared/features/ui/audit/Finding")
local SourceRules = require("../src/shared/features/ui/audit/SourceRules")
local StaticRules = require("../src/shared/features/ui/audit/StaticRules")

local findings: { Finding.Finding } = {}
local files = 0
-- A template has no committed pieces until a game extracts its kit into assets/ui: nothing to audit.
local categories: { string } = if fs.isDir("assets/ui") then fs.readDir("assets/ui") else {}
for _, category in categories do
    for _, file in fs.readDir(`assets/ui/{category}`) do
        local path = `assets/ui/{category}/{file}`
        files += 1
        for _, root in roblox.deserializeModel(fs.readFile(path)) do
            for _, finding in StaticRules.auditRoot(root, path) do
                table.insert(findings, finding)
            end
        end
    end
end

-- Source rule: a raw list/grid layout or a literal gap outside the primitive (ADR 0045).
local function scanDir(dir: string)
    for _, entry in fs.readDir(dir) do
        local path = `{dir}/{entry}`
        if fs.isDir(path) then
            scanDir(path)
        elseif string.sub(entry, -5) == ".luau" then
            files += 1
            for _, finding in SourceRules.scan(path, fs.readFile(path)) do
                table.insert(findings, finding)
            end
        end
    end
end
if fs.isDir("src") then
    scanDir("src")
end

for _, finding in findings do
    print(Finding.format(finding))
end
local summary = serde.encode(
    "json",
    { files = files, total = #findings, byRule = Finding.countByRule(findings) },
    true
)
local out = process.args[1]
if out ~= nil then
    fs.writeFile(out, summary)
end
print(`ui-audit: {files} files, {#findings} findings`)
if #findings > 0 then
    process.exit(1)
end
