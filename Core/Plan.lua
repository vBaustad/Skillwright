-- Skillwright - plan: runs the route solver for a character's profession and keeps the result
-- until something that changes the answer happens (mode, learned recipes, prices, trainer facts).
local ADDON, SW = ...
local Plan = {}
SW.Plan = Plan

local cache = {}    -- [prof] = route

function Plan.Count(id, withBank)
    return C_Item.GetItemCount(id, withBank) or 0
end

function Plan.Invalidate(prof)
    if prof then cache[prof] = nil else wipe(cache) end
    SW.Fire("PLAN_CHANGED", prof)
end

function SW.SetMode(mode)
    if mode ~= "cheap" and mode ~= "fast" then return end
    SW.Settings().mode = mode
    Plan.Invalidate()
    SW.msg("route mode: %s", mode == "cheap" and "|cffffd100cheapest|r" or "|cffffd100fastest|r")
end

-- The specialization key the data uses ("Dragonscale", "Goblin" ...) for a character's profession.
function Plan.Spec(prof)
    local cp = SW.CharProf(prof)
    if cp.spec then return cp.spec end
    local specs = SW.PROFESSIONS[prof] and SW.PROFESSIONS[prof].specs
    if specs and cp.specName then
        for _, key in ipairs(specs) do
            if cp.specName:find(key, 1, true) then return key end
        end
    end
end

function Plan.Options(prof, from)
    local db, cp = SW.DB(), SW.CharProf(prof)
    local s = SW.Settings()
    return {
        from = math.max(1, from or cp.rank or 1),
        to = SW.MAX_RANK,
        mode = s.mode,
        known = cp.known,
        learnRanks = db.learnRanks,
        vendorPrices = db.vendor,
        market = SW.Prices.Market,
        allowCamp = false,       -- recipes that need a camp station (Tanning Rack, Master Forge ...) stay out
        preferVendor = s.preferVendor,
        owned = Plan.OwnedTools(),
        haveMats = s.useOwned ~= false and Plan.HaveMats(prof) or nil,
        spec = Plan.Spec(prof),
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
end

-- Materials this profession's recipes use, worked out once per profession.
local matsOf = {}
local function ProfessionMats(prof)
    local set = matsOf[prof]
    if set then return set end
    set = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        local mats = r[10]
        for i = 1, #mats, 2 do set[mats[i]] = true end
    end
    matsOf[prof] = set
    return set
end

-- Materials you already have enough of to be worth using: at least MIN_HAVE in the bags or bank, and not
-- something you'd regret burning - nothing worth more than HAVE_MAX_VALUE each, nothing rare or better.
local MIN_HAVE = 10
local HAVE_MAX_VALUE = 10000     -- 1g per unit
local haveSig = {}

function Plan.HaveMats(prof)
    local have, sig = {}, {}
    for id in pairs(ProfessionMats(prof)) do
        local count = Plan.Count(id, true)
        if count >= MIN_HAVE then
            local quality = C_Item.GetItemQualityByID(id)
            local facts = SW.Data.items[id]
            local unit = SW.Prices.Market(id)
                or (facts and facts[1] > 0 and facts[1])
                or (facts and facts[2] * 4)
                or 0
            if (not quality or quality < 3) and unit <= HAVE_MAX_VALUE then
                have[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    haveSig[prof] = table.concat(sig, ",")
    return have
end

-- Tools the character has (bags or bank): rods, hammers, spanners ...
local ownedSig
function Plan.OwnedTools()
    local owned, sig = {}, {}
    for _, t in pairs(SW.Data.tools or {}) do
        for _, id in ipairs(t[3]) do
            if Plan.Count(id, true) > 0 then
                owned[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    return owned, table.concat(sig, ",")
end

-- The first tool a step still needs, live (it disappears the moment the tool is in your bags).
function Plan.PendingTool(step, owned)
    owned = owned or Plan.OwnedTools()
    for _, t in ipairs(step.prereqs or {}) do
        if not SW.Solver.HasTool(t.category, owned) then return t end
    end
end

-- The route for a profession from the character's current rank. Solved from rank 1 for professions
-- the character doesn't have (preview). Re-solved when the rank leaves the cached route.
function Plan.Route(prof)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = cache[prof]
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return r end
    if r and rank >= r.to and not r.gapAt and r.to >= SW.MAX_RANK then return r end
    local t = debugprofilestop and debugprofilestop()
    r = SW.Solver.Solve(prof, Plan.Options(prof, rank))
    if r then
        if t then SW.dbg("solved %s from %d in %.0f ms", SW.ProfName(prof), rank, debugprofilestop() - t) end
        cache[prof] = r
    end
    return r
end

-- Index of the step the rank falls in (#steps + 1 when past the route).
function Plan.StepIndex(route, rank)
    for i, s in ipairs(route.steps) do
        if rank < s.to then return i end
    end
    return #route.steps + 1
end

local Count = function(...) return Plan.Count(...) end

-- Expected crafts left in a step from `rank` (the solver's numbers, re-summed from where you are now).
function Plan.CraftsLeft(step, rank)
    local sum, r = 0, math.max(rank, step.from)
    local ups = 1
    while r < step.to do
        local p = SW.Solver.Chance(step.yellow, step.grey, r)
        if p <= 0 then break end
        sum = sum + 1 / p
        r = r + ups
    end
    return math.ceil(sum - 1e-6)
end

-- Everything the guide shows about the step you're on.
function Plan.Current(prof)
    local route = Plan.Route(prof)
    if not route then return nil end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local idx = Plan.StepIndex(route, rank)
    local step = route.steps[idx]
    if not step then return { route = route, done = true, rank = rank } end
    local left = math.max(1, Plan.CraftsLeft(step, rank))
    -- A tool still to make (or buy) comes first: the step can't be crafted without it.
    local tool = Plan.PendingTool(step)
    local srcMats = step.mats
    if tool then
        left = 1
        srcMats = tool.mats
    end
    local mats, craftable = {}, nil
    for _, m in ipairs(srcMats) do
        local need = m.per * left
        local have = Count(m.id, true)
        local bags = Count(m.id, false)
        mats[#mats + 1] = { id = m.id, per = m.per, need = need, have = have, bank = math.max(0, have - bags),
                            short = math.max(0, need - have), unit = m.unit, priceSource = m.priceSource }
        local can = math.floor(bags / m.per)
        craftable = craftable and math.min(craftable, can) or can
    end
    local craftSpell = tool and tool.spell or step.spell
    return {
        route = route, idx = idx, step = step, rank = rank, left = left, mats = mats, tool = tool,
        craftable = math.min(craftable or (tool and 1 or 0), left),
        known = craftSpell and SW.Prof.Knows(prof, craftSpell) or false,
        color = tool and tool.yellow and SW.Solver.Color(tool.yellow, tool.grey, rank)
            or SW.Solver.Color(step.yellow, step.grey, rank),
    }
end

-- Materials for the rest of the route, grouped by trainer tier. Current step counted from the rank.
function Plan.Shopping(prof)
    local route = Plan.Route(prof)
    if not route then return {} end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local owned = Plan.OwnedTools()
    local groups, byTier = {}, {}
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local tier
            for _, t in ipairs(SW.TIERS) do
                if s.from < t.cap then tier = t break end
            end
            tier = tier or SW.TIERS[#SW.TIERS]
            local g = byTier[tier.cap]
            if not g then
                g = { tier = tier, mats = {}, order = {}, cost = 0 }
                byTier[tier.cap] = g
                groups[#groups + 1] = g
            end
            local crafts = rank > s.from and Plan.CraftsLeft(s, rank) or s.crafts
            local function add(id, qty, unit, src)
                local e = g.mats[id]
                if not e then
                    e = { id = id, need = 0, unit = unit, priceSource = src }
                    g.mats[id] = e
                    g.order[#g.order + 1] = e
                end
                e.need = e.need + qty
                g.cost = g.cost + qty * unit
            end
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then
                    if t.buy then
                        add(t.item, 1, t.cost or 0, "vendor")
                    else
                        for _, m in ipairs(t.mats) do add(m.id, m.per, m.unit, m.priceSource) end
                    end
                end
            end
            for _, m in ipairs(s.mats) do add(m.id, m.per * crafts, m.unit, m.priceSource) end
        end
    end
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.order) do
            e.have = Count(e.id, true)
            e.short = math.max(0, e.need - e.have)
        end
    end
    return groups
end

-- Totals for the rest of the route: crafts and gold still to spend.
function Plan.Remaining(prof)
    local route = Plan.Route(prof)
    if not route then return 0, 0 end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local owned = Plan.OwnedTools()
    local crafts, cost = 0, 0
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local n = rank > s.from and Plan.CraftsLeft(s, rank) or s.crafts
            crafts = crafts + n
            cost = cost + n * s.costEach
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then cost = cost + (t.cost or 0) end
            end
        end
    end
    return crafts, cost
end

-- The next trainer tier to learn, when the rank is close to (or at) the current cap.
function Plan.TrainingDue(prof)
    local cp = SW.CharProf(prof)
    local rank, max = cp.rank or 0, cp.max or 0
    if max <= 0 or max >= SW.MAX_RANK then return nil end
    for _, t in ipairs(SW.TIERS) do
        if t.cap > max then
            if rank >= t.need and rank >= max - 10 then return t end
            return nil
        end
    end
end

for _, ev in ipairs({ "RECIPES_CHANGED", "TRAINER_FACTS", "PRICES_CHANGED" }) do
    SW.Listen(ev, function(prof)
        if type(prof) == "number" then Plan.Invalidate(prof) else Plan.Invalidate() end
    end)
end
-- A tool arriving in (or leaving) the bags changes which recipes are possible.
-- Picking things up shouldn't re-plan constantly: only when the set of tools, or of materials we have
-- enough of, actually changes - and then at most once every few seconds.
SW.On("BAG_UPDATE_DELAYED", function()
    SW.Coalesce("bagsChanged", 3, function()
        local _, sig = Plan.OwnedTools()
        local changed = ownedSig and sig ~= ownedSig
        ownedSig = sig
        if SW.Settings().useOwned ~= false then
            for prof in pairs(cache) do
                local before = haveSig[prof]
                Plan.HaveMats(prof)
                if before and haveSig[prof] ~= before then changed = true end
            end
        end
        if changed then Plan.Invalidate() end
    end)
end)
-- Vendor prices change the plan only a little; re-plan when the merchant closes.
SW.Listen("MERCHANT_CHANGED", function()
    if not (MerchantFrame and MerchantFrame:IsShown()) then SW.Debounce("replanVendor", 1, function() Plan.Invalidate() end) end
end)
