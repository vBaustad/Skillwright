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
function SW.KnownRecipes(prof)
    if not GetNumTradeSkills or not GetTradeSkillInfo then return nil end
    local open = GetTradeSkillLine and GetTradeSkillLine()
    if open ~= prof then return nil end
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

-- A full plan for the step you're currently on: how many crafts remain, whether the
-- recipe is learned, and per-mat have / need / how many to buy. craftableNow = how many
-- you can make right now limited by your *farmed* mats (vendor mats can always be bought),
-- so buyNow tells you exactly how much vendor stock to buy to use up what you have.
function SW.StepPlan(prof, rank)
    local steps = SW.PATHS[prof]
    if not steps then return nil end
    local idx = SW.CurrentStepIndex(steps, rank)
    if idx > #steps then return { done = true } end
    local s = steps[idx]
    local span = math.max(1, s.to - s.from)
    local remaining = math.max(1, math.ceil(s.qty * math.max(0, s.to - math.max(rank, s.from)) / span))

    local kset = SW.KnownRecipes(prof)
    local known = kset and (kset[s.recipe] and true or false) or nil

    -- craftableNow: limited by farmed mats only (vendor mats can be bought) - drives buyNow.
    -- craftableHave: limited by ALL mats in your bags right now - drives the Craft button.
    local mats, craftableNow, craftableHave = {}, nil, nil
    for _, m in ipairs(s.mats) do
        local name, total, id = m[1], m[2], m[3]
        local have = (id and GetItemCount(id, true)) or 0       -- bags + bank
        local bank = (id and math.max(0, have - GetItemCount(id))) or 0  -- bank-only
        local need = math.ceil(total * remaining / s.qty)
        local vendor = SW.IsVendorMat(id)
        mats[#mats + 1] = { name = name, id = id, total = total, have = have, bank = bank, need = need,
                            short = math.max(0, need - have), vendor = vendor }
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
        if e.vendor then
            e.buyNow = math.max(0, math.ceil(e.total * craftableNow / s.qty) - e.have)
        else
            e.buyNow = 0
        end
    end

    return { done = false, step = s, idx = idx, remaining = remaining,
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
