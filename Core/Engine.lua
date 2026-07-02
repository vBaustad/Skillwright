-- Skillwright - engine: current-skill detection and material math.
local ADDON, SW = ...
local DB, CharDB = SW.DB, SW.CharDB

-- Scan the skills window for a profession's rank (works with the trade window closed,
-- as long as its skill header is expanded - which it is by default).
local function ScanSkill(prof)
    if not GetNumSkillLines then return nil end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if not isHeader and name == prof and rank and rank > 0 then return rank end
    end
end

-- Accurate when the profession's trade window is open (GetTradeSkillLine); else the
-- skills-window scan; else the last value cached for this character.
function SW.CurrentSkill(prof)
    if GetTradeSkillLine then
        local n, rank = GetTradeSkillLine()
        if n and n == prof and rank and rank > 0 then CharDB().skill[prof] = rank; return rank end
    end
    local scanned = ScanSkill(prof)
    if scanned then CharDB().skill[prof] = scanned; return scanned end
    return CharDB().skill[prof] or 0
end

-- Index of the step you're on (from <= rank < to); #steps+1 means done.
function SW.CurrentStepIndex(steps, rank)
    for i, s in ipairs(steps) do if rank < s.to then return i end end
    return #steps + 1
end

-- Materials still required from the current skill onward. order[] preserves first-seen
-- order; req[name] = { qty, id }.
function SW.RemainingMats(prof, rank)
    local req, order = {}, {}
    for _, s in ipairs(SW.PATHS[prof] or {}) do
        if rank < s.to then
            for _, m in ipairs(s.mats) do
                local name, qty, id = m[1], m[2], m[3]
                if not req[name] then order[#order + 1] = name; req[name] = { qty = 0, id = id } end
                req[name].qty = req[name].qty + qty
            end
        end
    end
    return req, order
end

-- Remaining materials grouped into trainer tiers (each step counts toward the tier its
-- 'from' falls in). The current step is rank-adjusted; finished steps are dropped.
-- Returns ordered tiers: { lo, hi, name, current, mats = { {name, id, qty}, ... } }.
function SW.TierShopping(prof, rank)
    local steps = SW.PATHS[prof]
    if not steps then return {} end
    local out = {}
    for _, tier in ipairs(SW.TIERS) do
        local lo, hi, name = tier[1], tier[2], tier[3]
        if rank < hi then
            local req, order = {}, {}
            for _, s in ipairs(steps) do
                if s.from >= lo and s.from < hi and rank < s.to then
                    local mult = 1
                    if rank >= s.from then
                        local span = math.max(1, s.to - s.from)
                        mult = math.ceil(s.qty * (s.to - math.max(rank, s.from)) / span) / s.qty
                    end
                    for _, m in ipairs(s.mats) do
                        local nm, total, id = m[1], m[2], m[3]
                        if not req[nm] then order[#order + 1] = nm; req[nm] = { qty = 0, id = id } end
                        req[nm].qty = req[nm].qty + math.ceil(total * mult)
                    end
                end
            end
            if #order > 0 then
                local mats = {}
                for _, nm in ipairs(order) do mats[#mats + 1] = { name = nm, id = req[nm].id, qty = req[nm].qty } end
                out[#out + 1] = { lo = lo, hi = hi, name = name, current = (rank >= lo and rank < hi), mats = mats }
            end
        end
    end
    return out
end

-- The professions this character actually has (scanned from the skills window), each
-- tagged with whether Skillwright has a leveling guide for it. Guided first, then by name.
function SW.CharProfessions()
    local known = {}
    for _, p in ipairs(SW.PROFESSIONS) do known[p] = true end
    local found = {}
    if GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and known[name] and rank and rank > 0 then
                found[#found + 1] = { name = name, rank = rank, max = maxRank or 0, hasGuide = SW.HasGuide(name) }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.hasGuide ~= b.hasGuide then return a.hasGuide end
        return a.name < b.name
    end)
    return found
end

-- Every profession Skillwright knows about, each flagged learned/unlearned with its rank, so
-- the dashboard can list them all (greying out the ones this character hasn't picked up) and
-- still let you open any guide to preview or plan it. Learned ones sort first, then by name.
function SW.AllProfessions()
    local learned = {}
    if GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and rank and rank > 0 then learned[name] = { rank = rank, max = maxRank or 0 } end
        end
    end
    local out = {}
    for _, name in ipairs(SW.PROFESSIONS) do
        local l = learned[name]
        out[#out + 1] = {
            name = name, learned = l ~= nil,
            rank = l and l.rank or 0, max = l and l.max or 0,
            hasGuide = SW.HasGuide(name), gathering = SW.GATHERING[name] and true or false,
        }
    end
    table.sort(out, function(a, b)
        if a.learned ~= b.learned then return a.learned end
        return a.name < b.name
    end)
    return out
end

-- Rough effort to take a profession from `rank` to max: step / craft / total-mat counts for
-- a craft path, or remaining segment count for a gathering route. Powers the dashboard row
-- tooltips so you can size up how grindy each profession is (works for unlearned ones too).
function SW.ProfEffort(prof, rank)
    rank = rank or 0
    if SW.ROUTES[prof] then
        local segs = 0
        for _, seg in ipairs(SW.ROUTES[prof]) do if rank < seg.to then segs = segs + 1 end end
        return { gathering = true, segments = segs }
    end
    local steps = SW.PATHS[prof]
    if not steps then return nil end
    local nsteps, crafts, mats = 0, 0, 0
    for _, s in ipairs(steps) do
        if rank < s.to then
            nsteps = nsteps + 1
            crafts = crafts + (s.qty or 0)
            for _, m in ipairs(s.mats) do mats = mats + (m[2] or 0) end
        end
    end
    return { steps = nsteps, crafts = crafts, mats = mats }
end

-- True if this character has actually learned the profession (rank > 0 in the skills list).
-- Drives the "preview overview" shown on the Now tab for professions you don't have yet.
function SW.IsLearned(prof)
    if not GetNumSkillLines then return true end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if not isHeader and name == prof and rank and rank > 0 then return true end
    end
    return false
end

function SW.ActiveProfession()
    local db = DB()
    if db.active and SW.HasGuide(db.active) then return db.active end
    local names = {}
    for p in pairs(SW.PATHS) do names[#names + 1] = p end
    for p in pairs(SW.ROUTES) do names[#names + 1] = p end
    table.sort(names)
    return names[1]
end

function SW.ItemIcon(id)
    return (id and select(5, GetItemInfoInstant(id))) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Set of recipe names you've already learned, but only when this profession's trade
-- window is open (otherwise we can't read the list). nil = "can't tell right now".
-- The set of recipe names in the currently-open trade window. This is only a display hint
-- ("have you learned this step's recipe?"), so we scan whichever trade window is open instead of
-- demanding an exact profession-name match: GetTradeSkillLine()'s name doesn't always equal our
-- stored profession name, and that mismatch used to make the "you haven't trained this yet" hint
-- silently never appear. (RecipeIndex, which drives actual crafting, keeps its strict match.)
function SW.KnownRecipes(prof)
    if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillLine) then return nil end
    if not GetTradeSkillLine() then return nil end   -- no trade window open at all
    local n = GetNumTradeSkills()
    if not n or n == 0 then return nil end
    local set, count = {}, 0
    for i = 1, n do
        local name, stype = GetTradeSkillInfo(i)
        if name and stype ~= "header" then set[name] = true; count = count + 1 end
    end
    if count == 0 then return nil end
    return set
end

-- Live per-craft reagents for a recipe, read straight from the open trade window. Returns
-- { {name, id, perCraft}, ... }, or nil when this profession's window isn't open or the recipe
-- isn't learned. Lets the plan mirror the game exactly instead of trusting our static data.
function SW.LiveReagents(prof, recipeName)
    if not (GetTradeSkillNumReagents and SW.RecipeIndex) then return nil end
    local idx = SW.RecipeIndex(prof, recipeName)   -- only non-nil while prof's window is open
    if not idx then return nil end
    local out = {}
    for i = 1, (GetTradeSkillNumReagents(idx) or 0) do
        local name, _, count = GetTradeSkillReagentInfo(idx, i)
        local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(idx, i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if name and count and count > 0 and id then
            out[#out + 1] = { name = name, id = id, perCraft = count }
        end
    end
    return (#out > 0) and out or nil
end

-- A full plan for the step you're currently on: how many crafts remain, whether the
-- recipe is learned, and per-mat have / need / how many to buy. craftableNow = how many
-- you can make right now limited by your *farmed* mats (vendor mats can always be bought).
-- buyNow (vendor mats only) = how much supplier stock you still need for the whole step,
-- so you can stock up on thread/dye/salt at the vendor before the farmed mats are in hand.
function SW.StepPlan(prof, rank)
    local steps = SW.PATHS[prof]
    if not steps then return nil end
    local idx = SW.CurrentStepIndex(steps, rank)
    if idx > #steps then return { done = true } end
    local s = steps[idx]
    local span = math.max(1, s.to - s.from)
    local remaining = math.max(1, math.ceil(s.qty * math.max(0, s.to - math.max(rank, s.from)) / span))
    -- Bare minimum crafts: best case every craft gives +1 skill, so you'd need only the
    -- remaining skill points. (remaining above is padded for green/yellow skill-up misses.)
    -- The gap between the two is the buffer - showing it stops players over-farming mats.
    local minCrafts = math.max(1, s.to - math.max(rank, s.from))

    local kset = SW.KnownRecipes(prof)
    local known = kset and (kset[s.recipe] and true or false) or nil

    -- When this recipe's trade window is open, trust the game's own reagent list over our
    -- static data: per-craft amounts and item IDs then exactly match reality (and any data
    -- error self-corrects). Total for the step = live per-craft x the planned craft count.
    -- Falls back to our data when the window is closed or the recipe isn't learned yet.
    local srcMats, live = s.mats, SW.LiveReagents(prof, s.recipe)
    if live then
        srcMats = {}
        for _, r in ipairs(live) do srcMats[#srcMats + 1] = { r.name, r.perCraft * s.qty, r.id } end
    end

    -- craftableNow: limited by farmed mats only (vendor mats can be bought) - "craft N now" text.
    -- craftableHave: limited by ALL mats in your bags right now - drives the Craft button.
    local mats, craftableNow, craftableHave = {}, nil, nil
    for _, m in ipairs(srcMats) do
        local name, total, id = m[1], m[2], m[3]
        local have = (id and GetItemCount(id, true)) or 0       -- bags + bank
        local bank = (id and math.max(0, have - GetItemCount(id))) or 0  -- bank-only
        local need = math.ceil(total * remaining / s.qty)
        local minNeed = math.ceil(total * minCrafts / s.qty)
        local vendor = SW.IsVendorMat(id)
        mats[#mats + 1] = { name = name, id = id, total = total, have = have, bank = bank, need = need,
                            minNeed = minNeed, short = math.max(0, need - have), vendor = vendor }
        local perCraft = total / s.qty
        local can = (perCraft > 0) and math.floor(have / perCraft) or remaining
        craftableHave = (craftableHave == nil) and can or math.min(craftableHave, can)
        if not vendor then
            craftableNow = (craftableNow == nil) and can or math.min(craftableNow, can)
        end
    end
    if craftableNow == nil then craftableNow = remaining end
    if craftableHave == nil then craftableHave = remaining end
    craftableNow = math.max(0, math.min(craftableNow, remaining))
    craftableHave = math.max(0, math.min(craftableHave, remaining))

    for _, e in ipairs(mats) do
        -- Supplier mats: buy the whole step's shortfall (need - have), independent of how
        -- many you can craft right now. This is what lets you stock up on thread/dye/salt
        -- at the vendor before the farmed mats are in your bags.
        if e.vendor then
            e.buyNow = math.max(0, e.need - e.have)
        else
            e.buyNow = 0
        end
    end

    return { done = false, step = s, idx = idx, remaining = remaining, minCrafts = minCrafts,
             craftableNow = craftableNow, craftableHave = craftableHave, known = known, mats = mats }
end

-- Trade-skill list index of a recipe by name (only when that prof's window is open).
function SW.RecipeIndex(prof, name)
    if not GetNumTradeSkills or not GetTradeSkillInfo then return nil end
    local open = GetTradeSkillLine and GetTradeSkillLine()
    if open ~= prof then return nil end
    for i = 1, GetNumTradeSkills() do
        local n, stype = GetTradeSkillInfo(i)
        if n == name and stype ~= "header" then return i end
    end
end

-- Data QA: with a crafting profession's trade window open, compare every learned recipe in
-- our path against the game's real reagents and print any mismatch (wrong item ID, wrong
-- per-craft amount, or a reagent we list / omit). Recipes you haven't learned are skipped.
function SW.VerifyData()
    local prof = GetTradeSkillLine and GetTradeSkillLine()
    if not prof or not SW.PATHS[prof] then
        SW.msg("open a guided crafting profession's window, then run |cffffd100/sw verify|r.")
        return
    end
    local checked, issues = 0, 0
    for _, s in ipairs(SW.PATHS[prof]) do
        local live = SW.LiveReagents(prof, s.recipe)
        if live then
            checked = checked + 1
            local byId = {}
            for _, r in ipairs(live) do byId[r.id] = r end
            for _, m in ipairs(s.mats) do
                local name, total, id = m[1], m[2], m[3]
                local perCraft = total / s.qty
                local lr = byId[id]
                if not lr then
                    issues = issues + 1
                    SW.msg(("|cffff5555%s|r: data lists |cffffffff%s|r (id %d) but the recipe doesn't use it."):format(s.recipe, name, id))
                elseif math.abs(lr.perCraft - perCraft) > 0.001 then
                    issues = issues + 1
                    SW.msg(("|cffffcc00%s|r: |cffffffff%s|r is %s/craft in data but %d/craft in game."):format(s.recipe, name, tostring(perCraft), lr.perCraft))
                end
                byId[id] = nil
            end
            for id, lr in pairs(byId) do
                issues = issues + 1
                SW.msg(("|cffff5555%s|r: recipe needs |cffffffff%s|r (id %d, %d/craft) but our data is missing it."):format(s.recipe, lr.name, id, lr.perCraft))
            end
        end
    end
    SW.msg(("verify: checked %d learned recipe(s) for %s - |cff%s|r."):format(
        checked, prof, issues == 0 and "66ff66no mismatches" or ("ff5555" .. issues .. " issue(s)")))
end
