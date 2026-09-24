-- Skillwright - what we publish to the rest of YippYapp: which items matter to this character's crafting.
-- BagWarden asks per item while the bags are open, so every answer here is a table lookup; the tables are
-- built once and thrown away when the recipes, the ranks or the plan change.
--
-- Scope, deliberately narrow: materials of recipes this character KNOWS, whatever the current route still
-- needs, and the tools the route asks for. Nothing wider - protecting every reagent of every recipe in the
-- profession would protect half the auction house, and an over-eager protector is worse than a missing one,
-- because it quietly stops BagWarden freeing anything.
local ADDON, SW = ...
local R = {}
SW.Reagents = R

local known                  -- [itemID] = profession name: a material of a recipe this character knows
local needed                 -- [itemID] = true: the current route still needs it
local tools                  -- [itemID] = true: a tool the route asks for

function R.Forget()
    known, needed, tools = nil, nil, nil
end

-- Materials of every recipe the character knows, per profession they have.
local function BuildKnown()
    known = {}
    for _, prof in ipairs(SW.Prof.Mine()) do
        local data = SW.Data.professions[prof]
        local cp = SW.CharProf(prof)
        if data and cp.known then
            local name = SW.ProfName(prof)
            for _, r in ipairs(data[2]) do
                if cp.known[r[1]] then
                    local mats = r[10]
                    for i = 1, #mats, 2 do known[mats[i]] = known[mats[i]] or name end
                end
            end
        end
    end
end

-- What the route still wants: the steps ahead and the tools they need. Only from a route we already have -
-- answering a question must never start a solve.
local function BuildNeeded()
    needed, tools = {}, {}
    for _, prof in ipairs(SW.Prof.Mine()) do
        local route = SW.Plan.RouteIfReady(prof)
        if route then
            local rank = math.max(1, SW.Prof.Rank(prof))
            for _, s in ipairs(route.steps) do
                if s.to > rank then
                    for _, m in ipairs(s.mats or {}) do needed[m.id] = true end
                    for _, t in ipairs(s.prereqs or {}) do
                        for _, id in ipairs(SW.Solver.ToolItems(t.category) or {}) do tools[id] = true end
                        for i = 1, #(t.mats or {}), 2 do needed[t.mats[i]] = true end
                    end
                end
            end
        end
    end
end

-- "critical" while the route still needs it, "useful" for the rest of this character's crafting, else nil.
function R.Tier(itemID)
    if not itemID then return nil end
    if not known then BuildKnown() end
    if not needed then BuildNeeded() end
    if needed[itemID] or tools[itemID] then return "critical" end
    if known[itemID] then return "useful" end
    return nil
end

-- Why this item is worth keeping, in words a tooltip can show; nil means "no opinion".
function R.Keep(itemID)
    local tier = R.Tier(itemID)
    if not tier then return nil end
    if tier == "critical" then
        return (tools and tools[itemID]) and "a tool your profession route needs"
            or "needed for your profession route", tier
    end
    return ((known[itemID] or "profession") .. " reagent"), tier
end

-- The plan, the recipes and the ranks all change what matters; so does learning a new profession.
for _, ev in ipairs({ "PLAN_CHANGED", "RECIPES_CHANGED", "RANKS_CHANGED", "COLORS_CHANGED" }) do
    SW.Listen(ev, R.Forget)
end

SW.Listen("LOGIN", function()
    local LIB = SW.LIB
    if LIB and LIB.ProvideData then
        LIB.ProvideData("SkillwrightReagents", { Keep = R.Keep, Tier = R.Tier })
    end
end)
