--!strict
--[[
    Reads the lcov file written by `luau --coverage` and prints line coverage per file and in
    total (ADR 0017). Run with: lune run scripts/coverage_report <lcov> <threshold> [<root>]
    (default root: src). Exit code 1 when the TOTAL is under the threshold or when a file that
    is not excluded never appears in the lcov (a module no test loads would hide at 0 %).

    Excluded (never counted, never required to appear):
    - path prefixes in EXCLUDED_PREFIXES (type-only ports, generated code);
    - any path segment named vendor, types, tests or generated;
    - Main.* entry points;
    - any file that touches the engine (`game:...` or `game.X`): engine runs are not this gate.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

type GateConfig = { coverageExcludedPrefixes: { string }? }
type FileStats = { path: string, hit: number, total: number }

-- src/client is engine presenters (Instances); its rules live in pure modules under src/shared.
local EXCLUDED_PREFIXES: { string } = { "src/shared/ports/", "src/client/" }
local EXCLUDED_SEGMENTS: { string } = { "vendor", "types", "tests", "generated" }

-- A game adds its own exclusions in gate.config.json, the same file analyze.ps1 and CI read.
if fs.isFile("gate.config.json") then
    local gate = serde.decode("json", fs.readFile("gate.config.json")) :: GateConfig
    local prefixes: { string } = gate.coverageExcludedPrefixes or {}
    for _, prefix in prefixes do
        table.insert(EXCLUDED_PREFIXES, prefix)
    end
end

local function normalize(path: string): string
    local cleaned = string.gsub(path, "\\", "/")
    cleaned = string.gsub(cleaned, "^%./", "")
    return cleaned
end

local function parseLcov(text: string): { [string]: FileStats }
    local byPath: { [string]: FileStats } = {}
    local current: FileStats? = nil
    for line in string.gmatch(text, "[^\r\n]+") do
        local path = string.match(line, "^SF:(.+)$")
        if path ~= nil then
            current = { path = normalize(path), hit = 0, total = 0 }
        elseif line == "end_of_record" then
            if current ~= nil then
                byPath[current.path] = current
            end
            current = nil
        elseif current ~= nil then
            local hits = string.match(line, "^DA:%d+,(%d+)$")
            if hits ~= nil then
                current.total += 1
                if (tonumber(hits) :: number) > 0 then
                    current.hit += 1
                end
            end
        end
    end
    return byPath
end

local function touchesEngine(path: string): boolean
    local source = fs.readFile(path)
    return string.find(source, "game:%u") ~= nil or string.find(source, "game%.%u") ~= nil
end

local function exclusionReason(path: string): string?
    for _, prefix in EXCLUDED_PREFIXES do
        if string.sub(path, 1, #prefix) == prefix then
            return "excluded prefix"
        end
    end
    for segment in string.gmatch(path, "[^/]+") do
        for _, excluded in EXCLUDED_SEGMENTS do
            if segment == excluded then
                return `excluded folder {excluded}`
            end
        end
        if string.match(segment, "^Main%.") ~= nil then
            return "entry point"
        end
    end
    if touchesEngine(path) then
        return "touches the engine"
    end
    return nil
end

local function listLuau(dir: string, out: { string })
    for _, name in fs.readDir(dir) do
        local path = `{dir}/{name}`
        if fs.isDir(path) then
            listLuau(path, out)
        elseif string.sub(name, -5) == ".luau" then
            table.insert(out, path)
        end
    end
end

local args = process.args
local lcovPath = args[1] or "logs/coverage.lcov"
local threshold = tonumber(args[2] or "75") or 75
local root = string.gsub(args[3] or "src", "/$", "")

local byPath = parseLcov(fs.readFile(lcovPath))
local files: { string } = {}
listLuau(root, files)
table.sort(files)

local rows: { FileStats } = {}
local missing: { string } = {}
local excluded: { string } = {}
for _, path in files do
    local reason = exclusionReason(path)
    if reason ~= nil then
        table.insert(excluded, `{path} ({reason})`)
    else
        local stats = byPath[path]
        if stats == nil then
            table.insert(missing, path)
        else
            table.insert(rows, stats)
        end
    end
end

local hit, total = 0, 0
for _, row in rows do
    hit += row.hit
    total += row.total
    local percent = if row.total == 0 then 100 else row.hit / row.total * 100
    print(string.format("%6.1f%%  %4d/%-4d  %s", percent, row.hit, row.total, row.path))
end
for _, path in missing do
    print(`   MISSING  {path} (not loaded by any test)`)
end
print(`\nExcluded from the gate: {#excluded} file(s)`)
for _, entry in excluded do
    print(`  - {entry}`)
end
local overall = if total == 0 then 0 else hit / total * 100
print(
    string.format("\nTOTAL  %.1f%%  (%d/%d lines)  threshold %d%%", overall, hit, total, threshold)
)
if overall < threshold or #missing > 0 then
    process.exit(1)
end
