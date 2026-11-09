--!strict
--[[
    Source rule of the UI ecosystem: a list or grid layout is born only inside the primitive
    (Atoms.list, ScrollList, Stack), which takes its gap and padding from tokens. Reads source
    text, so it runs under Lune over `src/` with no Studio (`lune run scripts/ui-audit`).

      UI-RAW-LAYOUT   a raw list or grid layout instance outside an allowed file
      UI-LITERAL-GAP  a list Padding assigned from number literals (a number, not a token)

    Decision: docs/adr/0045-ui-spacing-and-platform-aware-controls.md.
]]

local Finding = require("./Finding")

export type Finding = Finding.Finding

local SourceRules = {}

--- Files that may create a raw layout, matched as a path suffix. Keep this list short: it is
--- the primitive. A game adds nothing here; it calls the primitive.
SourceRules.ALLOWED_SUFFIXES = {
    "presenters/ui/system/Atoms.luau",
    "presenters/ui/system/ScrollList.luau",
    -- Theme-based sibling of Atoms (the legacy kit path); its stack asserts a gap above 0.
    "presenters/ui/Widgets.luau",
    -- This rule names the patterns it forbids.
    "ui/audit/SourceRules.luau",
}

local RAW_LAYOUTS = { 'Instance.new("UIListLayout")', 'Instance.new("UIGridLayout")' }

local function stripComment(line: string): string
    local index = string.find(line, "--", 1, true)
    if index == nil then
        return line
    end
    return string.sub(line, 1, index - 1)
end

local function allowed(path: string, suffixes: { string }): boolean
    local normal = string.gsub(path, "\\", "/")
    for _, suffix in suffixes do
        if string.sub(normal, -#suffix) == suffix then
            return true
        end
    end
    return false
end

--- Scans one file. `allowedSuffixes` defaults to ALLOWED_SUFFIXES.
function SourceRules.scan(path: string, source: string, allowedSuffixes: { string }?): { Finding }
    local out: { Finding } = {}
    local free = allowed(path, allowedSuffixes or SourceRules.ALLOWED_SUFFIXES)
    local number = 0
    for raw in string.gmatch(source .. "\n", "(.-)\n") do
        number += 1
        local line = stripComment(raw)
        if not free then
            for _, pattern in RAW_LAYOUTS do
                if string.find(line, pattern, 1, true) ~= nil then
                    table.insert(
                        out,
                        Finding.new(
                            "UI-RAW-LAYOUT",
                            "error",
                            path,
                            `line {number}`,
                            "raw list/grid layout: use Atoms.list, Stack or ScrollList"
                        )
                    )
                end
            end
        end
        if
            string.match(line, "%.Padding%s*=%s*UDim%.new%(%s*[%d%.]+%s*,%s*[%d%.]+%s*%)") ~= nil
        then
            table.insert(
                out,
                Finding.new(
                    "UI-LITERAL-GAP",
                    "error",
                    path,
                    `line {number}`,
                    "list Padding is a number literal: take it from a spacing token"
                )
            )
        end
    end
    return out
end

return SourceRules
