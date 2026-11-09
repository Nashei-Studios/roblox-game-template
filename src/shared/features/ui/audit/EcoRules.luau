--!strict
--[[
    Layout and control rules of the UI ecosystem, over plain measurements (rectangles, names), so
    they are unit tested with fixtures and run unchanged under Lune and in a playtest
    (client/presenters/ui/audit/EcoAudit collects the measurements). Rule ids:

      UI-LIST-GAP         siblings of a list are closer than the spacing token
      UI-LIST-OVERLAP     siblings of a list overlap
      UI-CARD-INSET       text inside a card is closer to the card edge than the padding token
      UI-TEXT-LOST        a label does not fit and is cut, and is not marked Truncatable
      UI-HUD-UNREGISTERED a HUD button has no entry in the ControlRegistry
      UI-CONTROL-PLATFORM a control is visible on a scheme that does not list it

    Decision: docs/adr/0045-ui-spacing-and-platform-aware-controls.md.
]]

local Finding = require("./Finding")
local Geometry = require("./Geometry")
local ControlRegistry = require("../ControlRegistry")
local InputScheme = require("../InputScheme")

export type Rect = Geometry.Rect
export type Finding = Finding.Finding

local EcoRules = {}

--- Siblings of one list or grid. `rects` are the visible items in screen pixels; `minGap` is
--- the spacing token (px). One finding per rule per list, with the pair count and the worst gap.
function EcoRules.siblingGaps(
    scope: string,
    path: string,
    rects: { Rect },
    minGap: number
): { Finding }
    local touching, overlapping, worst = 0, 0, math.huge
    for first = 1, #rects do
        for second = first + 1, #rects do
            local a, b = rects[first], rects[second]
            -- Two layers on the same box (a text and its shadow) are not neighbours.
            if not (Geometry.contains(a, b, 1) or Geometry.contains(b, a, 1)) then
                if Geometry.overlapArea(a, b) > 0 then
                    overlapping += 1
                else
                    local gap = Geometry.gap(a, b)
                    if gap < minGap - 0.5 then
                        touching += 1
                        worst = math.min(worst, gap)
                    end
                end
            end
        end
    end
    local out: { Finding } = {}
    if touching > 0 then
        table.insert(
            out,
            Finding.new(
                "UI-LIST-GAP",
                "error",
                scope,
                path,
                `{touching} item pairs closer than {minGap} px (min {worst})`
            )
        )
    end
    if overlapping > 0 then
        table.insert(
            out,
            Finding.new("UI-LIST-OVERLAP", "error", scope, path, `{overlapping} item pairs overlap`)
        )
    end
    return out
end

--- A text inside a card: every side must keep `minInset` px between the text and the card edge.
--- A text that is not inside the card is not this rule's business.
function EcoRules.cardInset(
    scope: string,
    path: string,
    card: Rect,
    text: Rect,
    minInset: number
): { Finding }
    if not Geometry.contains(card, text, 0) then
        return {}
    end
    local left = text.x - card.x
    local top = text.y - card.y
    local right = card.x + card.width - (text.x + text.width)
    local bottom = card.y + card.height - (text.y + text.height)
    local least = math.min(left, top, right, bottom)
    if least >= minInset - 0.5 then
        return {}
    end
    return {
        Finding.new(
            "UI-CARD-INSET",
            "error",
            scope,
            path,
            `text is {least} px from the card edge, the padding token is {minInset} px`
        ),
    }
end

--- A label whose text does not fit (TextFits false) or is cut loses content. Only a label the
--- game marked on purpose (attribute `Truncatable`) may be cut.
function EcoRules.textLost(
    scope: string,
    path: string,
    fits: boolean,
    truncatable: boolean
): { Finding }
    if fits or truncatable then
        return {}
    end
    return {
        Finding.new(
            "UI-TEXT-LOST",
            "error",
            scope,
            path,
            "text does not fit its box and is cut; resize it or mark it Truncatable on purpose"
        ),
    }
end

--- HUD buttons by instance name: each one must be registered with its purpose and schemes.
function EcoRules.hudRegistration(
    scope: string,
    buttonNames: { string },
    registry: ControlRegistry.Registry
): { Finding }
    local out: { Finding } = {}
    for _, name in buttonNames do
        if not ControlRegistry.has(registry, name) then
            table.insert(
                out,
                Finding.new(
                    "UI-HUD-UNREGISTERED",
                    "error",
                    scope,
                    name,
                    "HUD button has no ControlRegistry entry (purpose and schemes)"
                )
            )
        end
    end
    return out
end

--- The controls visible while `scheme` is active: each must list that scheme.
function EcoRules.controlsOnScheme(
    scope: string,
    scheme: InputScheme.Scheme,
    visibleNames: { string },
    registry: ControlRegistry.Registry
): { Finding }
    local out: { Finding } = {}
    for _, name in visibleNames do
        if
            ControlRegistry.has(registry, name)
            and not ControlRegistry.visibleOn(registry, name, scheme)
        then
            table.insert(
                out,
                Finding.new(
                    "UI-CONTROL-PLATFORM",
                    "error",
                    `{scope}@{scheme}`,
                    name,
                    `visible on {scheme} but its registered schemes do not include it`
                )
            )
        end
    end
    return out
end

return EcoRules
